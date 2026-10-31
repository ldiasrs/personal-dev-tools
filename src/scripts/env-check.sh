#!/usr/bin/env bash
#
# env-check.sh — find the .env mistakes that fail silently.
#
# Usage:
#   env-check.sh [ENV_FILE] [EXAMPLE_FILE]
#
# Defaults: ./.env against ./.env.example (the example is optional).
#
# Reports, by key name and line number only (values are never printed):
#   duplicate   the key is set twice; dotenv keeps one and drops the other
#   unquoted #  an unquoted value contains `#`; dotenv may cut it there
#   missing     the key is in the example but not in the env file
#   extra       the key is in the env file but not in the example
#
# Exit code 1 when a duplicate, unquoted `#` or missing key is found.
# Extra keys are informational only.
set -uo pipefail

case "${1:-}" in
  -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
esac

ENV_FILE="${1:-.env}"
EXAMPLE_FILE="${2:-.env.example}"

c_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m✗ %s\033[0m\n' "$*"; }

[ -f "$ENV_FILE" ] || { c_err "env file not found: $ENV_FILE"; exit 1; }

# Prints "<line>\t<key>\t<value>" for every assignment, skipping comments.
assignments() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      line = $0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      eq = index(line, "=")
      if (eq == 0) next
      key = substr(line, 1, eq - 1)
      gsub(/[[:space:]]/, "", key)
      printf "%d\t%s\t%s\n", NR, key, substr(line, eq + 1)
    }
  ' "$1"
}

keys_of() { assignments "$1" | cut -f2 | sort -u; }

problems=0

duplicates="$(assignments "$ENV_FILE" | awk -F'\t' '
  { lines[$2] = lines[$2] ? lines[$2] "," $1 : $1; count[$2]++ }
  END { for (k in count) if (count[k] > 1) printf "%s (lines %s)\n", k, lines[k] }
' | sort)"
if [ -n "$duplicates" ]; then
  c_err "duplicate keys in $ENV_FILE — only one value wins:"
  printf '%s\n' "$duplicates" | sed 's/^/    /'
  problems=1
fi

unquoted_hash="$(assignments "$ENV_FILE" | awk -F'\t' '
  {
    value = $3
    sub(/^[[:space:]]+/, "", value)
    first = substr(value, 1, 1)
    if (first != "\"" && first != "'\''" && index(value, "#") > 0)
      printf "%s (line %s)\n", $2, $1
  }
')"
if [ -n "$unquoted_hash" ]; then
  c_err "unquoted values containing # in $ENV_FILE — single-quote them:"
  printf '%s\n' "$unquoted_hash" | sed 's/^/    /'
  problems=1
fi

if [ -f "$EXAMPLE_FILE" ]; then
  missing="$(comm -23 <(keys_of "$EXAMPLE_FILE") <(keys_of "$ENV_FILE"))"
  extra="$(comm -13 <(keys_of "$EXAMPLE_FILE") <(keys_of "$ENV_FILE"))"
  if [ -n "$missing" ]; then
    c_err "keys in $EXAMPLE_FILE missing from $ENV_FILE:"
    printf '%s\n' "$missing" | sed 's/^/    /'
    problems=1
  fi
  if [ -n "$extra" ]; then
    c_warn "keys in $ENV_FILE not in $EXAMPLE_FILE:"
    printf '%s\n' "$extra" | sed 's/^/    /'
  fi
else
  c_warn "no $EXAMPLE_FILE to compare against; checked duplicates and # only"
fi

[ "$problems" -eq 0 ] && c_ok "$ENV_FILE looks good"
exit "$problems"
