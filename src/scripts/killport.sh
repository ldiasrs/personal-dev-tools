#!/usr/bin/env bash
#
# killport.sh — free one or more TCP ports.
#
# Usage:
#   killport.sh [-f|--force] PORT [PORT...]
#
# Shows what is listening on each port, sends SIGTERM, waits up to 5 seconds,
# then SIGKILLs whatever is left. --force skips straight to SIGKILL.
#
# Examples:
#   killport.sh 3000
#   killport.sh 3000 3001 3002
#   killport.sh -f 5432
set -uo pipefail

FORCE=0
PORTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) FORCE=1; shift ;;
    -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *[!0-9]*|'') printf '\033[31m✗ not a port: %s\033[0m\n' "$1" >&2; exit 1 ;;
    *) PORTS[${#PORTS[@]}]="$1"; shift ;;
  esac
done
[ ${#PORTS[@]} -gt 0 ] || { echo "Usage: killport.sh [-f] PORT [PORT...]" >&2; exit 1; }

c_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }

listeners() { lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | sort -u; }

wait_until_free() {
  local port="$1" tries=0
  while [ -n "$(listeners "$port")" ] && [ "$tries" -lt 10 ]; do
    sleep 0.5
    tries=$((tries + 1))
  done
}

failed=0
for port in "${PORTS[@]}"; do
  pids="$(listeners "$port")"
  if [ -z "$pids" ]; then
    c_ok "port $port is already free"
    continue
  fi

  c_warn "port $port is held by:"
  ps -o pid=,command= -p $(echo $pids | tr ' ' ',') | sed 's/^/    /'

  if [ "$FORCE" -eq 0 ]; then
    kill $pids 2>/dev/null
    wait_until_free "$port"
  fi
  pids="$(listeners "$port")"
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null && wait_until_free "$port"

  if [ -n "$(listeners "$port")" ]; then
    c_err "port $port is still in use (try sudo)"
    failed=1
  else
    c_ok "port $port freed"
  fi
done
exit "$failed"
