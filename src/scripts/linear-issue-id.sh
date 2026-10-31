#!/usr/bin/env bash
# Resolve a Linear issue identifier (e.g. ENG-123) to its id, title, state and URL.
# Usage: LINEAR_API_KEY=... linear-issue-id.sh <ISSUE_IDENTIFIER>
set -euo pipefail
IDENTIFIER="${1:?Usage: linear-issue-id.sh <ISSUE_IDENTIFIER>}"
: "${LINEAR_API_KEY:?LINEAR_API_KEY is required}"

curl -sS https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d "{\"query\": \"query { issue(id: \\\"${IDENTIFIER}\\\") { id identifier title url state { name } assignee { name } } }\"}"
echo
