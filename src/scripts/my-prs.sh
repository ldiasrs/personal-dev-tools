#!/usr/bin/env bash
#
# my-prs.sh — your open pull requests across every repo, with CI and review.
#
# Usage:
#   my-prs.sh            PRs you authored
#   my-prs.sh --review   PRs that request your review directly (not via a team)
#   my-prs.sh --json     raw JSON instead of the table
#
# Columns: CI (✔ pass, ✗ fail, … pending, - none), review decision, draft
# flag, repo#number, title and last update. Needs `gh auth login`.
set -euo pipefail

FILTER="author:@me"
OUTPUT=table
for arg in "$@"; do
  case "$arg" in
    --review) FILTER="user-review-requested:@me" ;;
    --json) OUTPUT=json ;;
    -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# shellcheck disable=SC2016 # $q is a GraphQL variable, not a shell one
QUERY='query($q: String!) {
  search(query: $q, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number title url isDraft updatedAt reviewDecision
        repository { nameWithOwner }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
}'

result="$(gh api graphql -f query="$QUERY" -f q="is:pr is:open archived:false $FILTER sort:updated-desc")"

if [ "$OUTPUT" = json ]; then
  printf '%s\n' "$result" | jq '.data.search.nodes'
  exit 0
fi

printf '%s\n' "$result" | jq -r '
  def ci: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE")
    | {SUCCESS: "✔", FAILURE: "✗", ERROR: "✗", PENDING: "…", EXPECTED: "…"}[.] // "-";
  def review: {APPROVED: "approved", CHANGES_REQUESTED: "changes", REVIEW_REQUIRED: "needs-review"}[.reviewDecision // ""] // "-";
  .data.search.nodes
  | if length == 0 then "No open pull requests." else
      (["CI", "REVIEW", "DRAFT", "PR", "TITLE", "UPDATED"] | @tsv),
      (.[] | [ci, review, (if .isDraft then "draft" else "-" end),
              "\(.repository.nameWithOwner)#\(.number)",
              (.title | if length > 60 then .[:57] + "..." else . end),
              (.updatedAt[:10])] | @tsv)
    end
' | column -t -s $'\t'
