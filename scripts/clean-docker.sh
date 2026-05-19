#!/usr/bin/env bash
#
# clean-docker.sh — Conservative docker prune.
#
# Removes:
#   - stopped containers
#   - dangling images (no tag, not referenced by any container)
#   - unused networks
#   - build cache
#
# Does NOT touch:
#   - volumes (data-loss risk; pass --volumes to opt in)
#   - tagged images currently unused (pass --all-images to opt in)
#
# Usage:
#   sudo bash scripts/clean-docker.sh
#   sudo bash scripts/clean-docker.sh --volumes      # also prune unused volumes
#   sudo bash scripts/clean-docker.sh --all-images   # also remove unused tagged images
#   sudo bash scripts/clean-docker.sh --dry-run      # just report what would happen
#
set -euo pipefail

WITH_VOLUMES=0
WITH_ALL_IMAGES=0
DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --volumes)    WITH_VOLUMES=1 ;;
    --all-images) WITH_ALL_IMAGES=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo bash $0)" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not installed; nothing to do."
  exit 0
fi

hr() { printf '\n=== %s ===\n' "$1"; }

hr "Before"
docker system df

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

hr "Pruning stopped containers"
run docker container prune -f

hr "Pruning dangling images"
run docker image prune -f

if [[ $WITH_ALL_IMAGES -eq 1 ]]; then
  hr "Pruning ALL unused images (including tagged)"
  run docker image prune -af
fi

hr "Pruning unused networks"
run docker network prune -f

hr "Pruning build cache"
run docker builder prune -f

if [[ $WITH_VOLUMES -eq 1 ]]; then
  hr "Pruning unused volumes (DATA LOSS RISK — opted in)"
  run docker volume prune -f
fi

hr "After"
docker system df

echo
echo "Done."
