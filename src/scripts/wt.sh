#!/usr/bin/env bash
#
# wt.sh — create a ready-to-run git worktree for a branch.
#
# Usage:
#   wt.sh [--no-install] BRANCH [BASE]
#
# Run it from inside the repo. It:
#   1. fetches origin, then checks out BRANCH in a new worktree at
#      ../<repo>.worktrees/<branch>  (slashes become dashes). An existing
#      local or remote BRANCH is reused; otherwise it is created from BASE
#      (default: origin/<default branch>).
#   2. copies every ignored .env / .env.* file from the main checkout into
#      the same relative path, so the worktree runs with the same config.
#   3. installs dependencies from the lockfile it finds (pnpm, npm, yarn,
#      uv), unless --no-install.
#
# Examples:
#   wt.sh feature/login
#   wt.sh fix/typo origin/release-2
#   wt.sh --no-install spike/idea
#
# Remove one later with: git worktree remove ../<repo>.worktrees/<branch>
set -euo pipefail

INSTALL=1
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-install) INSTALL=0; shift ;;
    -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) ARGS[${#ARGS[@]}]="$1"; shift ;;
  esac
done
BRANCH="${ARGS[0]:?Usage: wt.sh [--no-install] BRANCH [BASE]}"
BASE="${ARGS[1]:-}"

c_info() { printf '\033[36m▸ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m! %s\033[0m\n' "$*"; }

MAIN_ROOT="$(git rev-parse --path-format=absolute --git-common-dir)"
MAIN_ROOT="$(dirname "$MAIN_ROOT")"
REPO_NAME="$(basename "$MAIN_ROOT")"
WT_PATH="$(dirname "$MAIN_ROOT")/$REPO_NAME.worktrees/$(printf '%s' "$BRANCH" | tr '/' '-')"

[ -e "$WT_PATH" ] && { echo "Already exists: $WT_PATH" >&2; exit 1; }

c_info "fetching origin"
git -C "$MAIN_ROOT" fetch --quiet --prune origin

if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  c_info "using local branch $BRANCH"
  git -C "$MAIN_ROOT" worktree add --quiet "$WT_PATH" "$BRANCH"
elif git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  c_info "tracking origin/$BRANCH"
  git -C "$MAIN_ROOT" worktree add --quiet --track -b "$BRANCH" "$WT_PATH" "origin/$BRANCH"
else
  if [ -z "$BASE" ]; then
    default_branch="$(git -C "$MAIN_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
    BASE="$default_branch"
  fi
  c_info "creating $BRANCH from $BASE"
  git -C "$MAIN_ROOT" worktree add --quiet --no-track -b "$BRANCH" "$WT_PATH" "$BASE"
fi
c_ok "worktree at $WT_PATH"

# Ignored dirs are listed collapsed (node_modules/), so this stays fast.
env_files="$(git -C "$MAIN_ROOT" ls-files --others --ignored --exclude-standard --directory \
  | awk -F/ '$NF ~ /^\.env(\..+)?$/')"
if [ -n "$env_files" ]; then
  while IFS= read -r file; do
    mkdir -p "$WT_PATH/$(dirname "$file")"
    cp -p "$MAIN_ROOT/$file" "$WT_PATH/$file"
    c_ok "copied $file"
  done <<< "$env_files"
else
  c_info "no ignored .env files to copy"
fi

if [ "$INSTALL" -eq 1 ]; then
  cd "$WT_PATH"
  if   [ -f pnpm-lock.yaml ];    then c_info "pnpm install"; pnpm install --frozen-lockfile
  elif [ -f package-lock.json ]; then c_info "npm ci";       npm ci
  elif [ -f yarn.lock ];         then c_info "yarn install"; yarn install --frozen-lockfile
  elif [ -f uv.lock ];           then c_info "uv sync";      uv sync
  else c_warn "no lockfile found; skipped install"
  fi
fi

c_ok "ready: cd \"$WT_PATH\""
