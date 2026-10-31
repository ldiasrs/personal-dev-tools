#!/usr/bin/env bash
#
# jwt.sh — decode a JWT locally (nothing is sent anywhere).
#
# Usage:
#   jwt.sh TOKEN
#   echo "$TOKEN" | jwt.sh
#   jwt.sh              reads the token from the clipboard (pbpaste)
#
# Prints the header and payload, then iat / nbf / exp as local dates and
# whether the token is expired. A leading "Bearer " is stripped. The
# signature is NOT verified.
set -euo pipefail

case "${1:-}" in
  -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
esac

if [ -n "${1:-}" ]; then
  TOKEN="$1"
elif [ ! -t 0 ]; then
  TOKEN="$(cat)"
else
  TOKEN="$(pbpaste)"
fi
TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]' | sed 's/^Bearer//')"

IFS='.' read -r HEADER PAYLOAD _SIGNATURE <<< "$TOKEN"
[ -n "${PAYLOAD:-}" ] || { echo "Not a JWT: expected header.payload.signature" >&2; exit 1; }

b64url_decode() {
  local data
  data="$(printf '%s' "$1" | tr '_-' '/+')"
  case $(( ${#data} % 4 )) in
    2) data="$data==" ;;
    3) data="$data=" ;;
  esac
  printf '%s' "$data" | base64 --decode
}

echo "── header"
b64url_decode "$HEADER" | jq .
echo "── payload"
PAYLOAD_JSON="$(b64url_decode "$PAYLOAD")"
printf '%s' "$PAYLOAD_JSON" | jq .

echo "── times"
now="$(date +%s)"
for claim in iat nbf exp; do
  value="$(printf '%s' "$PAYLOAD_JSON" | jq -r --arg c "$claim" '.[$c] // empty')"
  [ -n "$value" ] && printf '%-4s %s\n' "$claim" "$(date -r "$value" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -d "@$value")"
done

exp="$(printf '%s' "$PAYLOAD_JSON" | jq -r '.exp // empty')"
if [ -z "$exp" ]; then
  echo "no exp claim: the token never expires"
elif [ "$exp" -le "$now" ]; then
  printf '\033[31mEXPIRED %s minutes ago\033[0m\n' $(( (now - exp) / 60 ))
else
  printf '\033[32mvalid for %s more minutes\033[0m\n' $(( (exp - now) / 60 ))
fi
