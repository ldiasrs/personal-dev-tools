#!/usr/bin/env bash
#
# docker-clean.sh — reclaim Docker / Colima disk space.
#
# Usage:
#   docker-clean.sh [--yes] [--images] [--volumes]
#
# Without --yes it only shows what would be removed (dry run).
#
# Always removed:
#   - stopped containers
#   - dangling images (untagged layers)
#   - build cache
# Opt-in:
#   --images    also every image no container uses (re-pulled on next run)
#   --volumes   also anonymous volumes no container uses. Named volumes,
#               such as a local database's data, are kept.
set -uo pipefail

APPLY=0
ALL_IMAGES=0
VOLUMES=0
for arg in "$@"; do
  case "$arg" in
    --yes) APPLY=1 ;;
    --images) ALL_IMAGES=1 ;;
    --volumes) VOLUMES=1 ;;
    -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

c_info() { printf '\033[36m▸ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }

docker info >/dev/null 2>&1 || { echo "Docker is not running (try: colima start)" >&2; exit 1; }

# Anonymous volumes have 64-hex names. Selecting them by name, rather than
# `docker volume prune`, keeps named volumes safe on Docker versions whose
# prune also removes those.
anonymous_unused_volumes() {
  docker volume ls --quiet --filter dangling=true | grep -E '^[0-9a-f]{64}$' || true
}

c_info "disk usage"
docker system df

if [ "$APPLY" -eq 0 ]; then
  c_info "stopped containers"
  docker ps -a --filter status=exited --filter status=created --format '    {{.Names}}  ({{.Image}}, {{.Status}})'
  c_info "dangling images"
  docker images --filter dangling=true --format '    {{.ID}}  {{.Size}}'
  if [ "$ALL_IMAGES" -eq 1 ]; then
    c_info "images no container uses"
    used="$(docker ps -a --format '{{.Image}}' | sort -u)"
    docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' | while read -r image size; do
      printf '%s\n' "$used" | grep -qxF "$image" || printf '    %s  %s\n' "$image" "$size"
    done
  fi
  if [ "$VOLUMES" -eq 1 ]; then
    c_info "unused anonymous volumes"
    anonymous_unused_volumes | sed 's/^/    /'
  fi
  echo
  echo "Dry run. Re-run with --yes to remove the above."
  exit 0
fi

docker container prune -f
if [ "$ALL_IMAGES" -eq 1 ]; then docker image prune -a -f; else docker image prune -f; fi
docker builder prune -f
if [ "$VOLUMES" -eq 1 ]; then
  volumes="$(anonymous_unused_volumes)"
  [ -n "$volumes" ] && docker volume rm $volumes
fi

c_ok "done"
docker system df
