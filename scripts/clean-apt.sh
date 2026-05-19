#!/usr/bin/env bash
#
# clean-apt.sh — Reclaim space from APT on Debian/Ubuntu hosts.
#
# Does:
#   - apt-get clean      (empty /var/cache/apt/archives)
#   - apt-get autoclean  (remove obsolete .deb files only)
#   - apt-get autoremove (remove orphaned dependency packages)
#
# Does NOT upgrade or install anything. Safe and reversible
# (you can re-download packages from the mirror if needed).
#
# Usage:
#   sudo bash scripts/clean-apt.sh
#   sudo bash scripts/clean-apt.sh --dry-run
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo bash $0)" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found — not a Debian/Ubuntu host. Skipping."
  exit 0
fi

hr() { printf '\n=== %s ===\n' "$1"; }

hr "APT cache size before"
du -sh /var/cache/apt 2>/dev/null || true

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

hr "apt-get autoclean (obsolete .deb files)"
run apt-get autoclean -y

hr "apt-get clean (all cached .deb files)"
run apt-get clean -y

hr "apt-get autoremove (orphaned packages)"
run apt-get autoremove -y --purge

hr "APT cache size after"
du -sh /var/cache/apt 2>/dev/null || true

echo
echo "Done."
