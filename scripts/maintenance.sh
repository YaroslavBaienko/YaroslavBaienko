#!/usr/bin/env bash
#
# maintenance.sh — One-shot conservative server maintenance.
#
# Runs (in order):
#   1. audit-disk.sh    (before snapshot)
#   2. clean-logs.sh    (journald, /var/log, docker/nginx logs)
#   3. clean-apt.sh     (if Debian/Ubuntu)
#   4. clean-docker.sh  (if docker installed)
#   5. audit-disk.sh    (after snapshot)
#
# Each step is delegated to its dedicated script so behavior stays consistent.
#
# Usage:
#   sudo bash scripts/maintenance.sh
#   sudo bash scripts/maintenance.sh --dry-run
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
DRY_ARG=()
[[ $DRY_RUN -eq 1 ]] && DRY_ARG=(--dry-run)

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo bash $0)" >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

banner() {
  printf '\n############################################################\n'
  printf '## %s\n' "$1"
  printf '############################################################\n'
}

DF_BEFORE=$(df --output=avail -B1 / | tail -1)

banner "1/5  AUDIT (before)"
bash "$DIR/audit-disk.sh"

banner "2/5  CLEAN LOGS"
bash "$DIR/clean-logs.sh" "${DRY_ARG[@]}"

banner "3/5  CLEAN APT"
bash "$DIR/clean-apt.sh" "${DRY_ARG[@]}"

banner "4/5  CLEAN DOCKER"
bash "$DIR/clean-docker.sh" "${DRY_ARG[@]}"

banner "5/5  AUDIT (after)"
bash "$DIR/audit-disk.sh"

DF_AFTER=$(df --output=avail -B1 / | tail -1)
RECLAIMED=$(( DF_AFTER - DF_BEFORE ))
# Convert to MB for readability
MB=$(( RECLAIMED / 1048576 ))

printf '\n============================================================\n'
printf 'Maintenance complete.\n'
if [[ $DRY_RUN -eq 1 ]]; then
  printf '(dry-run: no actual changes)\n'
else
  printf 'Reclaimed on /: %s MB\n' "$MB"
fi
printf '============================================================\n'
