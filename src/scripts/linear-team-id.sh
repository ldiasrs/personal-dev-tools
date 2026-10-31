#!/usr/bin/env bash
# Look up a Linear team's id by its key (e.g. ENG).
# Usage: LINEAR_API_KEY=... linear-team-id.sh <TEAM_KEY>
set -euo pipefail
TEAM_KEY="${1:?Usage: linear-team-id.sh <TEAM_KEY>}"
: "${LINEAR_API_KEY:?LINEAR_API_KEY is required}"

curl -sS https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d "{\"query\": \"query { teams(filter: { key: { eq: \\\"${TEAM_KEY}\\\" } }) { nodes { id key name } } }\"}"
echo
