#!/bin/bash
set -euo pipefail

THRESHOLD_MEM_PERCENT=85
THRESHOLD_DISK_PERCENT=85
APP_DIR="${APP_DIR:-/app}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

section() {
  echo ""
  log "===== $* ====="
}

section "Kubernetes container cleanup check started"

section "Container info"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "App dir: $APP_DIR"

section "Memory check"

MEM_LIMIT_FILE="/sys/fs/cgroup/memory.max"
MEM_CURRENT_FILE="/sys/fs/cgroup/memory.current"

if [[ -f "$MEM_LIMIT_FILE" && -f "$MEM_CURRENT_FILE" ]]; then
  MEM_LIMIT=$(cat "$MEM_LIMIT_FILE")
  MEM_CURRENT=$(cat "$MEM_CURRENT_FILE")

  if [[ "$MEM_LIMIT" != "max" ]]; then
    MEM_PERCENT=$(( MEM_CURRENT * 100 / MEM_LIMIT ))
    echo "Memory usage: ${MEM_PERCENT}%"
    echo "Current: $(( MEM_CURRENT / 1024 / 1024 )) MiB"
    echo "Limit:   $(( MEM_LIMIT / 1024 / 1024 )) MiB"
  else
    MEM_PERCENT=0
    echo "No cgroup memory limit detected"
  fi
else
  MEM_PERCENT=0
  free -h || true
fi

section "Disk check"

DISK_PERCENT=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
df -h /

echo "Disk usage: ${DISK_PERCENT}%"

section "Top memory processes"
ps aux --sort=-%mem | head -10 || true

section "Cache size check"

du -sh /tmp 2>/dev/null || true
du -sh /var/tmp 2>/dev/null || true
du -sh /root/.cache 2>/dev/null || true
du -sh "$APP_DIR/node_modules/.cache" 2>/dev/null || true
du -sh "$APP_DIR" 2>/dev/null || true

SHOULD_CLEAN=false

if [[ "${MEM_PERCENT:-0}" -ge "$THRESHOLD_MEM_PERCENT" ]]; then
  log "Memory above threshold: ${MEM_PERCENT}% >= ${THRESHOLD_MEM_PERCENT}%"
  SHOULD_CLEAN=true
fi

if [[ "$DISK_PERCENT" -ge "$THRESHOLD_DISK_PERCENT" ]]; then
  log "Disk above threshold: ${DISK_PERCENT}% >= ${THRESHOLD_DISK_PERCENT}%"
  SHOULD_CLEAN=true
fi

if [[ "$SHOULD_CLEAN" != true ]]; then
  log "No cleanup needed. Exiting safely."
  exit 0
fi

section "Cleanup starting"

log "Cleaning temp directories"
find /tmp -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null || true

log "Cleaning package caches"
apt-get clean 2>/dev/null || true
yum clean all 2>/dev/null || true
dnf clean all 2>/dev/null || true
apk cache clean 2>/dev/null || true

log "Cleaning app caches"
rm -rf /root/.cache/* 2>/dev/null || true
rm -rf "$APP_DIR/node_modules/.cache" 2>/dev/null || true

log "Cleaning Python caches"
find "$APP_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true

section "After cleanup"
free -h || true
df -h /
du -sh /tmp 2>/dev/null || true
du -sh /var/tmp 2>/dev/null || true
du -sh /root/.cache 2>/dev/null || true

log "Cleanup finished"
