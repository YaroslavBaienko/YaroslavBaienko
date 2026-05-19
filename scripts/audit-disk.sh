#!/usr/bin/env bash
#
# audit-disk.sh — Read-only disk / log / docker audit. Makes no changes.
#
# Run as any user (some sections need root for full visibility):
#   bash scripts/audit-disk.sh
#   sudo bash scripts/audit-disk.sh   # recommended for complete /var/log read access
#
set -euo pipefail

hr() { printf '\n=== %s ===\n' "$1"; }

hr "Disk usage (all filesystems)"
df -hT -x tmpfs -x devtmpfs -x squashfs 2>/dev/null || df -h

hr "Inode usage"
df -hi -x tmpfs -x devtmpfs -x squashfs 2>/dev/null || df -hi

hr "Top 15 directories under / (depth 1)"
du -h -d1 -x / 2>/dev/null | sort -h | tail -15 || true

hr "Top 15 directories under /var (depth 1)"
du -h -d1 /var 2>/dev/null | sort -h | tail -15 || true

hr "Top 15 directories under /var/log"
du -h -d1 /var/log 2>/dev/null | sort -h | tail -15 || true

hr "Largest 20 files under /var/log"
find /var/log -type f -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -20 \
  | awk '{ printf "%10.1f MB  %s\n", $1/1048576, $2 }' || true

hr "journald disk usage"
if command -v journalctl >/dev/null 2>&1; then
  journalctl --disk-usage 2>/dev/null || echo "(need root)"
else
  echo "journalctl not installed"
fi

if command -v docker >/dev/null 2>&1; then
  hr "docker system df"
  docker system df 2>/dev/null || echo "(docker daemon unreachable / need root)"

  hr "Largest docker container log files"
  for cid in $(docker ps -aq 2>/dev/null); do
    lp=$(docker inspect --format='{{.LogPath}}' "$cid" 2>/dev/null || true)
    [[ -f "$lp" ]] && printf '%s\t%s\n' "$(stat -c%s "$lp" 2>/dev/null || echo 0)" "$lp"
  done | sort -rn | head -10 \
       | awk '{ printf "%10.1f MB  %s\n", $1/1048576, $2 }' || true
fi

hr "APT cache size (if Debian/Ubuntu)"
[[ -d /var/cache/apt ]] && du -sh /var/cache/apt 2>/dev/null || echo "no apt cache"

hr "Old kernels installed (Debian/Ubuntu)"
if command -v dpkg >/dev/null 2>&1; then
  dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2}' || true
fi

echo
echo "Done. No changes made."
