#!/usr/bin/env bash
#
# clean-logs.sh — Safe, conservative log cleanup for a Hetzner (or any Linux) host.
#
# Strategy:
#   1. Audit first — print what's eating space, no changes.
#   2. Conservative cleanup — vacuum journald, rotate, truncate large *.log files
#      that are still being written to (truncate preserves file handles so
#      services keep logging without restart), delete already-rotated logs >14d.
#   3. Re-audit so you can see what was reclaimed.
#
# Run as root (or via sudo). Pass --dry-run to skip the cleanup step.
#
#   sudo bash scripts/clean-logs.sh             # audit + clean
#   sudo bash scripts/clean-logs.sh --dry-run   # audit only
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root (try: sudo bash $0)" >&2
  exit 1
fi

hr() { printf '\n=== %s ===\n' "$1"; }

audit() {
  hr "Disk usage"
  df -h /

  hr "Top /var subdirectories"
  du -h -d1 /var 2>/dev/null | sort -h | tail -20 || true

  hr "Top /var/log subdirectories"
  du -h -d1 /var/log 2>/dev/null | sort -h | tail -20 || true

  hr "journald disk usage"
  journalctl --disk-usage 2>/dev/null || echo "journalctl not available"

  if command -v docker >/dev/null 2>&1; then
    hr "docker system df"
    docker system df || true
  fi

  hr "Largest individual log files"
  find /var/log -type f \( -name "*.log" -o -name "*.log.*" -o -name "*.gz" \) \
    -printf '%s\t%p\n' 2>/dev/null \
    | sort -rn | head -15 \
    | awk '{ printf "%10.1f MB  %s\n", $1/1048576, $2 }' || true
}

clean() {
  hr "Vacuuming systemd journal (keep 7d, cap 500MB)"
  journalctl --vacuum-time=7d || true
  journalctl --vacuum-size=500M || true

  hr "Forcing logrotate"
  if [[ -f /etc/logrotate.conf ]]; then
    logrotate -f /etc/logrotate.conf || true
  else
    echo "no /etc/logrotate.conf, skipping"
  fi

  hr "Truncating live *.log files >100MB in /var/log"
  # truncate is safe for files held open by running services (unlike rm).
  find /var/log -type f -name "*.log" -size +100M -print -exec truncate -s 0 {} \; 2>/dev/null || true

  hr "Deleting rotated logs older than 14 days"
  find /var/log -type f \
    \( -name "*.gz" -o -name "*.xz" -o -name "*.bz2" \
       -o -regex '.*\.[0-9]+$' -o -name "*.old" \) \
    -mtime +14 -print -delete 2>/dev/null || true

  if command -v docker >/dev/null 2>&1; then
    hr "Truncating docker container logs >100MB"
    # shellcheck disable=SC2046
    for f in $(docker ps -aq 2>/dev/null | xargs -r -I{} docker inspect --format='{{.LogPath}}' {} 2>/dev/null); do
      if [[ -f "$f" ]] && [[ $(stat -c%s "$f") -gt 104857600 ]]; then
        echo "truncating $f"
        truncate -s 0 "$f"
      fi
    done
  fi

  hr "Truncating nginx/apache access+error logs >100MB"
  for d in /var/log/nginx /var/log/apache2 /var/log/httpd; do
    [[ -d "$d" ]] || continue
    find "$d" -type f -name "*.log" -size +100M -print -exec truncate -s 0 {} \; 2>/dev/null || true
  done
}

echo "### AUDIT (before) ###"
audit

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "--dry-run set; skipping cleanup."
  exit 0
fi

echo
echo "### CLEANUP ###"
clean

echo
echo "### AUDIT (after) ###"
df -h /
journalctl --disk-usage 2>/dev/null || true
echo
echo "Done."
