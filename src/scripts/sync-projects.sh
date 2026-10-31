#!/usr/bin/env bash
#
# sync-projects.sh — keep every git repo under the projects root in sync.
#
# Usage:
#   sync-projects.sh [MODE] [OPTIONS] [REPO...]
#
# Modes (default: all, when none is passed):
#   all             pull-changes, then my-doc-sync, then branches-purge (dry run)
#   pull-changes    fetch + fast-forward every repo except the publish repos
#   my-doc-sync     commit, rebase and push the publish repos (my-docs)
#   branches-purge  delete merged branches and their worktrees
#   force-clean-all-branches-workingtrees-local
#                   DESTRUCTIVE: reset every repo to its default branch,
#                   dropping worktrees, local branches and uncommitted work.
#                   Never part of `all`.
#
# Options:
#   --yes           apply branches-purge or the force clean; without it they
#                   only print their plan (dry run)
#   --jobs N        repos handled at a time (default: 6; 1 = sequential)
#   -h, --help      show this help
#
# Arguments:
#   REPO...         repo directory names under the projects root; with none,
#                   every repo is handled
#
# Examples:
#   sync-projects.sh                          # everything, purge as a dry run
#   sync-projects.sh apps services            # everything, only for these repos
#   sync-projects.sh --jobs 1                 # everything, sequentially
#
#   sync-projects.sh pull-changes             # fast-forward every repo
#   sync-projects.sh pull-changes apps        # fast-forward only apps
#
#   sync-projects.sh my-doc-sync              # publish my-docs only
#
#   sync-projects.sh branches-purge           # show which merged branches go
#   sync-projects.sh branches-purge --yes     # delete merged branches now
#   sync-projects.sh branches-purge --yes services   # ...only in services
#
#   sync-projects.sh force-clean-all-branches-workingtrees-local
#                                             # dry run: list everything lost
#   sync-projects.sh force-clean-all-branches-workingtrees-local --yes services
#                                             # wipe services back to main
#
#   JOBS=2 PROJECTS=~/work sync-projects.sh   # env vars instead of flags
#   PUBLISH_REPOS="my-docs notes" sync-projects.sh my-doc-sync
#
# pull-changes
#   Fetches with --prune, then fast-forwards the CURRENT branch to its upstream.
#   Nothing is stashed, merged or rebased: a repo that cannot fast-forward
#   cleanly is reported and left untouched. Untracked files do not count as
#   dirty; git itself refuses if the pull would overwrite one. A summary table
#   flags every repo that is not on its default branch.
#
# my-doc-sync
#   On the default branch, every local change is committed ("sync <timestamp>"),
#   rebased onto the remote, and pushed. On any other branch it does nothing.
#
# branches-purge
#   A branch counts as merged when either holds:
#     - one of my merged PRs has that head branch, and the local tip is part of
#       what that PR shipped (catches squash merges);
#     - its upstream is gone and the tip is already in origin/<default>.
#   The default branch, the branch checked out in the main worktree, and locked
#   worktrees are never touched. A dirty worktree is kept (`worktree remove`
#   refuses it). Removing a worktree also deletes its ignored files (.env,
#   node_modules).
#
# force-clean-all-branches-workingtrees-local
#   For every repo except the publish repos: removes every linked worktree
#   (ignored files included), checks out the default branch discarding tracked
#   changes, deletes untracked files (ignored ones stay), deletes every other
#   local branch, then fast-forwards to the remote. Uncommitted work and commits
#   that exist on no remote are LOST; the plan lists them per branch. Locked
#   worktrees are kept.
#
# Overridable env vars:
#   PROJECTS        default: $HOME/Documents/projects
#   JOBS            default: 6
#   PUBLISH_REPOS   default: "my-docs"   (space-separated; "" disables)
#
# Exit code 1 if a repo could not be synced (fetch error, divergence, dirty
# tree, failed push), else 0. Repos with no remote or no upstream are not
# failures.
#
# Targets bash 3.2 (the /bin/bash macOS ships): no `wait -n`, no `local a=()`.
set -uo pipefail

PROJECTS="${PROJECTS:-$HOME/Documents/projects}"
JOBS="${JOBS:-6}"
PUBLISH_REPOS="${PUBLISH_REPOS-my-docs}"
FILTERS=()
MODE=all
CLEAN_APPLY=0

case "${1:-}" in
  all|pull-changes|my-doc-sync|branches-purge|force-clean-all-branches-workingtrees-local) MODE="$1"; shift ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS="${2:?--jobs needs a number}"; shift 2 ;;
    --yes) CLEAN_APPLY=1; shift ;;
    -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    -*) printf '\033[31m✗ unknown option: %s\033[0m\n' "$1" >&2; exit 1 ;;
    *) FILTERS[${#FILTERS[@]}]="$1"; shift ;;
  esac
done

c_info() { printf '\033[36m▸ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }

[ -d "$PROJECTS" ] || { c_err "PROJECTS is not a directory: $PROJECTS"; exit 1; }
case "$MODE" in all|branches-purge|force-clean-all-branches-workingtrees-local) ;; *)
  [ "$CLEAN_APPLY" -eq 0 ] || { c_err "--yes only applies to branches-purge and the force clean"; exit 1 ;}
esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sync-projects.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

wanted() {
  local name="$1" filter
  [ ${#FILTERS[@]} -eq 0 ] && return 0
  for filter in "${FILTERS[@]}"; do [ "$filter" = "$name" ] && return 0; done
  return 1
}

discover_repos() {
  local path name
  for path in "$PROJECTS"/*; do
    [ -d "$path" ] || continue
    [ -L "$path" ] && continue
    name="$(basename "$path")"
    wanted "$name" || continue
    git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || continue
    printf '%s\n' "$name"
  done
}

default_branch() {
  local repo="$1" head candidate
  head="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$head" ]; then printf '%s' "${head#origin/}"; return 0; fi
  for candidate in main master; do
    git -C "$repo" show-ref -q --verify "refs/remotes/origin/$candidate" && { printf '%s' "$candidate"; return 0; }
  done
  printf '%s' main
}

is_publish_repo() {
  case " $PUBLISH_REPOS " in *" $1 "*) return 0 ;; esac
  return 1
}

# name, branch, status, detail, on_default(yes|no) — one TAB-separated record.
# stdout of sync_repo is the record file, so every git call that can print must
# be redirected; `pull --rebase` writes its conflict report to stdout.
emit() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }

first_line() { tr '\n' ' ' <"$1" | cut -c1-58; }

BRANCH_WIDTH=40
fit_branch() {
  local branch="$1"
  if [ ${#branch} -le "$BRANCH_WIDTH" ]; then printf '%s' "$branch"; return 0; fi
  printf '%s…' "$(printf '%s' "$branch" | cut -c1-$((BRANCH_WIDTH - 1)))"
}

ahead_behind() {
  git -C "$1" rev-list --left-right --count "HEAD...$2" 2>/dev/null
}

# Commit everything, rebase onto the upstream, push. Called after the fetch and
# upstream checks in sync_repo, so the upstream ref is known to exist.
publish_repo() {
  local name="$1" branch="$2" upstream="$3" default="$4"
  local repo="$PROJECTS/$name" errfile="$WORK_DIR/$name.err"
  local changed=0 counts ahead behind summary=""

  if [ "$branch" != "$default" ]; then
    emit "$name" "$branch" skipped "publish only runs on $default" no
    return 0
  fi

  changed="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
  if [ "$changed" -gt 0 ]; then
    git -C "$repo" add -A >/dev/null 2>&1
    if ! git -C "$repo" commit -q -m "sync $(date '+%Y-%m-%d %H:%M')" >"$errfile" 2>&1; then
      emit "$name" "$branch" failed "commit: $(first_line "$errfile")" yes
      return 0
    fi
    summary="committed $changed file(s)"
  fi

  counts="$(ahead_behind "$repo" "$upstream")"
  behind="${counts##*[!0-9]}"
  if [ "${behind:-0}" -gt 0 ]; then
    if ! git -C "$repo" pull -q --rebase origin "$branch" >"$errfile" 2>&1; then
      git -C "$repo" rebase --abort >/dev/null 2>&1
      emit "$name" "$branch" failed "rebase conflict — resolve by hand" yes
      return 0
    fi
    summary="${summary:+$summary, }pulled +$behind"
  fi

  counts="$(ahead_behind "$repo" "$upstream")"
  ahead="${counts%%[!0-9]*}"
  if [ "${ahead:-0}" -gt 0 ]; then
    if ! git -C "$repo" push -q origin "$branch" >"$errfile" 2>&1; then
      emit "$name" "$branch" failed "push: $(first_line "$errfile")" yes
      return 0
    fi
    summary="${summary:+$summary, }pushed $ahead commit(s)"
  fi

  if [ -z "$summary" ]; then
    emit "$name" "$branch" "up to date" "nothing to publish" yes
  else
    emit "$name" "$branch" published "$summary" yes
  fi
}

sync_repo() {
  local name="$1" repo="$PROJECTS/$1" errfile="$WORK_DIR/$1.err"
  local branch default upstream counts ahead behind on_default

  branch="$(git -C "$repo" branch --show-current 2>/dev/null)"

  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    emit "$name" "${branch:-detached}" "no remote" "nothing to sync" yes
    return 0
  fi

  if ! git -C "$repo" fetch --prune --quiet origin 2>"$errfile"; then
    emit "$name" "${branch:-detached}" "fetch failed" "$(first_line "$errfile")" yes
    return 0
  fi

  # Read after the fetch: a first fetch can be what creates origin/HEAD.
  default="$(default_branch "$repo")"
  on_default=no
  [ "$branch" = "$default" ] && on_default=yes

  if [ -z "$branch" ]; then
    emit "$name" detached skipped "detached HEAD" no
    return 0
  fi

  # for-each-ref, not `rev-parse @{u}`: rev-parse exits non-zero but still prints
  # the literal "@{u}" when the configured upstream ref is gone, which reads as a
  # valid upstream and makes a stale branch look up to date.
  upstream="$(git -C "$repo" for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>/dev/null)"
  if [ -z "$upstream" ]; then
    emit "$name" "$branch" "no upstream" "local-only branch" "$on_default"
    return 0
  fi

  if ! git -C "$repo" show-ref -q --verify "refs/remotes/$upstream"; then
    emit "$name" "$branch" "upstream gone" "$upstream deleted on remote" "$on_default"
    return 0
  fi

  if is_publish_repo "$name"; then
    publish_repo "$name" "$branch" "$upstream" "$default"
    return 0
  fi

  counts="$(ahead_behind "$repo" "$upstream")"
  ahead="${counts%%[!0-9]*}"
  behind="${counts##*[!0-9]}"
  ahead="${ahead:-0}"
  behind="${behind:-0}"

  if [ "$behind" -eq 0 ]; then
    if [ "$ahead" -eq 0 ]; then
      emit "$name" "$branch" "up to date" "even with $upstream" "$on_default"
    else
      emit "$name" "$branch" "up to date" "$ahead unpushed, nothing to pull" "$on_default"
    fi
    return 0
  fi

  if [ "$ahead" -ne 0 ]; then
    emit "$name" "$branch" diverged "$ahead ahead / $behind behind — rebase by hand" "$on_default"
    return 0
  fi

  # Untracked files never block a fast-forward: git itself refuses when one
  # would be overwritten, and that surfaces as `failed` below.
  if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    emit "$name" "$branch" dirty "$behind behind, tracked changes not committed" "$on_default"
    return 0
  fi

  if git -C "$repo" merge --ff-only --quiet "$upstream" >"$errfile" 2>&1; then
    emit "$name" "$branch" pulled "+$behind commits" "$on_default"
  else
    emit "$name" "$branch" failed "$(first_line "$errfile")" "$on_default"
  fi
}

# Worktrees of one repo show up as sibling directories, so cleanup runs once per
# main worktree rather than once per discovered directory.
main_worktrees() {
  local name
  while read -r name; do
    [ -n "$name" ] || continue
    git -C "$PROJECTS/$name" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p'
  done <<EOF
$1
EOF
}

# branch<TAB>path<TAB>locked(yes|no) for every linked worktree that has a branch.
linked_worktrees() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { path = substr($0, 10); branch = ""; locked = "no"; n++ }
    /^branch refs\/heads\// { branch = substr($0, 19) }
    /^locked/ { locked = "yes" }
    /^$/ { if (n > 1 && branch != "") print branch "\t" path "\t" locked; branch = "" }
    END { if (n > 1 && branch != "") print branch "\t" path "\t" locked }'
}

# headRefName<TAB>headRefOid of my merged PRs. Empty for non-GitHub remotes.
merged_pr_heads() {
  (cd "$1" && gh pr list --state merged --author @me --limit 3000 \
    --json headRefName,headRefOid --jq '.[] | "\(.headRefName)\t\(.headRefOid)"') 2>/dev/null
}

is_ancestor() {
  git -C "$1" merge-base --is-ancestor "$2" "$3" >/dev/null 2>&1
}

# Prints why the branch counts as merged; returns 1 when it does not.
merged_reason() {
  local repo="$1" branch="$2" default="$3" prs="$4" pr_head upstream
  while IFS=$'\t' read -r _ pr_head; do
    is_ancestor "$repo" "refs/heads/$branch" "$pr_head" && { printf 'PR merged'; return 0; }
  done <<EOF
$(awk -F'\t' -v b="$branch" '$1 == b' "$prs")
EOF
  upstream="$(git -C "$repo" for-each-ref --format='%(upstream:short)' "refs/heads/$branch")"
  [ -n "$upstream" ] || return 1
  git -C "$repo" show-ref -q --verify "refs/remotes/$upstream" && return 1
  is_ancestor "$repo" "refs/heads/$branch" "origin/$default" || return 1
  printf 'in %s, upstream gone' "$default"
}

# repo, action, branch, detail — one TAB-separated record per cleanup decision.
clean_emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

clean_repo() {
  local repo="$1" name default current prs worktrees branch reason wt_path wt_locked
  name="$(basename "$repo")"
  # Merge detection reads remote refs, so refresh them when no sync did.
  [ "$MODE" = branches-purge ] && git -C "$repo" fetch --prune --quiet origin >/dev/null 2>&1
  default="$(default_branch "$repo")"
  current="$(git -C "$repo" branch --show-current 2>/dev/null)"
  prs="$WORK_DIR/clean-$name.prs"
  worktrees="$WORK_DIR/clean-$name.worktrees"
  merged_pr_heads "$repo" >"$prs"
  linked_worktrees "$repo" >"$worktrees"

  while read -r branch; do
    [ -n "$branch" ] || continue
    [ "$branch" = "$default" ] && continue
    [ "$branch" = "$current" ] && continue
    reason="$(merged_reason "$repo" "$branch" "$default" "$prs")" || continue

    wt_path="" wt_locked=no
    IFS=$'\t' read -r _ wt_path wt_locked <<EOF
$(awk -F'\t' -v b="$branch" '$1 == b' "$worktrees")
EOF

    if [ "$wt_locked" = yes ]; then
      clean_emit "$name" kept "$branch" "$reason, but worktree is locked"
      continue
    fi
    if [ "$CLEAN_APPLY" -eq 0 ]; then
      clean_emit "$name" "would delete" "$branch" "$reason${wt_path:+ (+ worktree $(basename "$wt_path"))}"
      continue
    fi
    if [ -n "$wt_path" ] && ! git -C "$repo" worktree remove "$wt_path" >/dev/null 2>&1; then
      clean_emit "$name" kept "$branch" "$reason, but worktree $(basename "$wt_path") is dirty"
      continue
    fi
    # -D, not -d: a squash-merged branch is never an ancestor of the default
    # branch, and merged_reason has already proved nothing local is lost.
    if git -C "$repo" branch -D "$branch" >/dev/null 2>&1; then
      clean_emit "$name" deleted "$branch" "$reason${wt_path:+ (+ worktree $(basename "$wt_path"))}"
    else
      clean_emit "$name" failed "$branch" "git branch -D refused"
    fi
  done <<EOF
$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)
EOF

  [ "$CLEAN_APPLY" -eq 1 ] && git -C "$repo" worktree prune >/dev/null 2>&1
  return 0
}

# path<TAB>locked(yes|no) for every linked worktree, detached ones included.
all_linked_worktrees() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { if (path != "" && n > 1) print path "\t" locked; path = substr($0, 10); locked = "no"; n++ }
    /^locked/ { locked = "yes" }
    END { if (path != "" && n > 1) print path "\t" locked }'
}

unpushed_commits() {
  git -C "$1" rev-list --count "refs/heads/$2" --not --remotes 2>/dev/null
}

# Describes what is lost, then (with --yes) does it. Plan and action share one
# path so the dry run cannot drift from what --yes executes.
force_clean_repo() {
  local repo="$1" name default current dirty branch unpushed wt_path wt_locked
  local verb_remove="would delete" verb_reset="would reset"
  name="$(basename "$repo")"
  if is_publish_repo "$name"; then
    clean_emit "$name" kept "-" "publish repo, never force-cleaned"
    return 0
  fi
  [ "$CLEAN_APPLY" -eq 1 ] && { verb_remove=deleted; verb_reset=reset; }

  git -C "$repo" fetch --prune --quiet origin >/dev/null 2>&1
  default="$(default_branch "$repo")"
  current="$(git -C "$repo" branch --show-current 2>/dev/null)"

  while IFS=$'\t' read -r wt_path wt_locked; do
    [ -n "$wt_path" ] || continue
    if [ "$wt_locked" = yes ]; then
      clean_emit "$name" kept "$(basename "$wt_path")" "worktree is locked"
      continue
    fi
    if [ "$CLEAN_APPLY" -eq 1 ] && ! git -C "$repo" worktree remove --force "$wt_path" >/dev/null 2>&1; then
      clean_emit "$name" failed "$(basename "$wt_path")" "git worktree remove refused"
      continue
    fi
    clean_emit "$name" "$verb_remove" "$(basename "$wt_path")" "worktree"
  done <<EOF
$(all_linked_worktrees "$repo")
EOF

  dirty="$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$current" != "$default" ] || [ "$dirty" -gt 0 ]; then
    if [ "$CLEAN_APPLY" -eq 1 ]; then
      git -C "$repo" checkout -q -f "$default" >/dev/null 2>&1
      git -C "$repo" reset -q --hard >/dev/null 2>&1
      git -C "$repo" clean -qfd >/dev/null 2>&1
    fi
    clean_emit "$name" "$verb_reset" "${current:-detached} -> $default" "$dirty changed/untracked path(s) discarded"
  fi

  while read -r branch; do
    [ -n "$branch" ] || continue
    [ "$branch" = "$default" ] && continue
    unpushed="$(unpushed_commits "$repo" "$branch")"
    if [ "$CLEAN_APPLY" -eq 1 ] && ! git -C "$repo" branch -D "$branch" >/dev/null 2>&1; then
      clean_emit "$name" failed "$branch" "git branch -D refused"
      continue
    fi
    clean_emit "$name" "$verb_remove" "$branch" "branch, ${unpushed:-0} unpushed commit(s) lost"
  done <<EOF
$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)
EOF

  if [ "$CLEAN_APPLY" -eq 1 ]; then
    git -C "$repo" worktree prune >/dev/null 2>&1
    git -C "$repo" merge --ff-only --quiet "origin/$default" >/dev/null 2>&1 \
      || clean_emit "$name" failed "$default" "could not fast-forward to origin/$default"
  fi
  return 0
}

clean_colour() {
  case "$1" in
    deleted|reset) printf 32 ;;
    "would delete"|"would reset") printf 36 ;;
    kept) printf 33 ;;
    *) printf 31 ;;
  esac
}

# Runs `$1 <item>` for each line of $2 in the background, $JOBS at a time,
# writing each item's stdout to $WORK_DIR/<prefix><basename>.out.
# bash 3.2 has no `wait -n`, so run fixed-size batches and wait for each.
run_batched() {
  local fn="$1" items="$2" prefix="$3" item batch=0
  while read -r item; do
    [ -n "$item" ] || continue
    "$fn" "$item" >"$WORK_DIR/$prefix$(basename "$item").out" &
    batch=$((batch + 1))
    if [ "$batch" -ge "$JOBS" ]; then wait; batch=0; fi
  done <<EOF
$items
EOF
  wait
}

status_colour() {
  case "$1" in
    pulled|published)       printf 32 ;;
    "up to date")           printf 90 ;;
    dirty|diverged|"upstream gone") printf 33 ;;
    "no remote"|"no upstream") printf 90 ;;
    *)                      printf 31 ;;
  esac
}

is_failure() {
  case "$1" in
    pulled|published|"up to date"|"no remote"|"no upstream") return 1 ;;
    *) return 0 ;;
  esac
}

# Keeps the repos the mode syncs: publish repos for my-doc-sync, the rest for
# pull-changes, both for all.
sync_targets() {
  local name
  while read -r name; do
    [ -n "$name" ] || continue
    case "$MODE" in
      pull-changes) is_publish_repo "$name" && continue ;;
      my-doc-sync) is_publish_repo "$name" || continue ;;
    esac
    printf '%s\n' "$name"
  done <<EOF
$1
EOF
}

# Prints the summary table and returns the number of repos that failed.
report_sync() {
  local targets="$1" name record r_name r_branch r_status r_detail r_on_default
  local branch_colour failures=0 off_default=""

  printf '\n'
  printf '  %-18s %-40s %-14s %s\n' REPO BRANCH STATUS DETAIL
  printf '  %-18s %-40s %-14s %s\n' \
    "------------------" "----------------------------------------" "--------------" "------------------------------"

  while read -r name; do
    [ -n "$name" ] || continue
    record="$(cat "$WORK_DIR/$name.out" 2>/dev/null)"
    [ -n "$record" ] || record="$(emit "$name" "?" failed "no result recorded" yes)"

    IFS=$'\t' read -r r_name r_branch r_status r_detail r_on_default <<EOF
$record
EOF

    is_failure "$r_status" && failures=$((failures + 1))
    branch_colour=0
    if [ "$r_on_default" = no ]; then
      branch_colour=33
      off_default="$off_default $r_name($r_branch)"
    fi

    printf '  %-18s \033[%sm%-40s\033[0m \033[%sm%-14s\033[0m %s\n' \
      "$r_name" "$branch_colour" "$(fit_branch "$r_branch")" "$(status_colour "$r_status")" "$r_status" "$r_detail"
  done <<EOF
$targets
EOF

  printf '\n'
  if [ -n "${off_default# }" ]; then
    c_warn "not on the default branch:${off_default}"
  else
    c_ok "every repo is on its default branch"
  fi
  return "$failures"
}

report_purge() {
  local targets="$1" prefix="${2:-clean-}" target records c_repo c_action c_branch c_detail

  printf '\n'
  if [ "$CLEAN_APPLY" -eq 1 ]; then c_info "$MODE"; else c_info "$MODE plan (dry run — add --yes to apply)"; fi
  records="$(while read -r target; do
    [ -n "$target" ] && cat "$WORK_DIR/$prefix$(basename "$target").out" 2>/dev/null
  done <<EOF
$targets
EOF
)"
  if [ -z "$records" ]; then
    c_ok "no merged branches to purge"
    return 0
  fi
  while IFS=$'\t' read -r c_repo c_action c_branch c_detail; do
    printf '  %-18s \033[%sm%-14s\033[0m %-40s %s\n' \
      "$c_repo" "$(clean_colour "$c_action")" "$c_action" "$(fit_branch "$c_branch")" "$c_detail"
  done <<EOF
$records
EOF
}

repos="$(discover_repos)"
[ -n "$repos" ] || { c_err "no git repos found under $PROJECTS"; exit 1; }

failures=0
if [ "$MODE" = force-clean-all-branches-workingtrees-local ]; then
  force_targets="$(main_worktrees "$repos" | sort -u)"
  c_warn "$MODE: $(printf '%s\n' "$force_targets" | wc -l | tr -d ' ') repos — uncommitted work and unpushed commits are discarded"
  run_batched force_clean_repo "$force_targets" force-
  report_purge "$force_targets" force-
  exit 0
fi

if [ "$MODE" != branches-purge ]; then
  targets="$(sync_targets "$repos")"
  if [ -z "$targets" ]; then
    c_warn "$MODE: no matching repos under $PROJECTS"
  else
    c_info "$MODE: $(printf '%s\n' "$targets" | wc -l | tr -d ' ') repos under $PROJECTS (jobs: $JOBS)"
    run_batched sync_repo "$targets" ""
    report_sync "$targets"
    failures=$?
  fi
fi

if [ "$MODE" = all ] || [ "$MODE" = branches-purge ]; then
  purge_targets="$(main_worktrees "$repos" | sort -u)"
  [ "$MODE" = branches-purge ] && c_info "branches-purge: $(printf '%s\n' "$purge_targets" | wc -l | tr -d ' ') repos under $PROJECTS (jobs: $JOBS)"
  run_batched clean_repo "$purge_targets" clean-
  report_purge "$purge_targets"
fi

if [ "$failures" -eq 0 ]; then
  c_ok "done"
else
  c_warn "$failures repo(s) need attention (see table)"
  exit 1
fi
