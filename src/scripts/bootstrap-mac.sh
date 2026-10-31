#!/usr/bin/env bash
#
# bootstrap-mac.sh — set up a new Mac from personal-dev-tools.
#
# Usage:
#   bootstrap-mac.sh [--dry-run]
#
# Every step is skipped when already done, so it is safe to re-run:
#   1. Xcode command line tools
#   2. Homebrew, then everything in the repo's Brewfile
#   3. oh-my-zsh
#   4. ~/.zshrc sources src/scripts/zshrc.sample
#   5. the Node version in NODE_VERSION via nvm
#   6. clones each repo in PERSONAL_REPOS into PERSONAL_DIR
#
# Restoring files from a mac-backup archive is separate: npm run mac-restore.
#
# Overridable env vars:
#   PERSONAL_DIR     default: $HOME/Documents/personal-projects
#   PERSONAL_REPOS   default: "git@github.com:ldiasrs/personal-dev-tools.git"
#                    (space-separated clone URLs)
#   NODE_VERSION     default: 22
set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  -h|--help) awk 'NR <= 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERSONAL_DIR="${PERSONAL_DIR:-$HOME/Documents/personal-projects}"
PERSONAL_REPOS="${PERSONAL_REPOS-git@github.com:ldiasrs/personal-dev-tools.git}"
NODE_VERSION="${NODE_VERSION:-22}"
ZSHRC_SAMPLE="$REPO_DIR/src/scripts/zshrc.sample"

c_info() { printf '\033[36m▸ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }

# Runs a step, or only prints it in a dry run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would run: %s\n' "$*"
  else
    "$@"
  fi
}

step_xcode_tools() {
  if xcode-select -p >/dev/null 2>&1; then c_ok "Xcode command line tools"; return; fi
  c_info "installing Xcode command line tools (finish the dialog, then re-run)"
  run xcode-select --install
  [ "$DRY_RUN" -eq 1 ] || exit 0
}

step_homebrew() {
  if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
    c_info "installing Homebrew"
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  c_ok "Homebrew"

  if command -v brew >/dev/null 2>&1 && brew bundle check --file="$REPO_DIR/Brewfile" >/dev/null 2>&1; then
    c_ok "Brewfile already satisfied"
  else
    c_info "installing the Brewfile"
    run brew bundle --file="$REPO_DIR/Brewfile"
  fi
}

step_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then c_ok "oh-my-zsh"; return; fi
  c_info "installing oh-my-zsh"
  run env RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

step_zshrc() {
  local line="source \"$ZSHRC_SAMPLE\""
  if grep -qF "$ZSHRC_SAMPLE" "$HOME/.zshrc" 2>/dev/null; then c_ok "~/.zshrc sources zshrc.sample"; return; fi
  c_info "adding zshrc.sample to ~/.zshrc"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    would append: %s\n' "$line"
  else
    printf '\n# personal-dev-tools aliases and toolchain setup\n%s\n' "$line" >> "$HOME/.zshrc"
  fi
}

step_node() {
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"
  local nvm_sh
  nvm_sh="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
  if [ ! -s "$nvm_sh" ]; then c_info "nvm not installed yet; skipped Node"; return; fi
  # shellcheck disable=SC1090
  . "$nvm_sh"
  if nvm ls "$NODE_VERSION" >/dev/null 2>&1; then c_ok "Node $NODE_VERSION"; return; fi
  c_info "installing Node $NODE_VERSION"
  run nvm install "$NODE_VERSION"
}

step_repos() {
  local url name
  for url in $PERSONAL_REPOS; do
    name="$(basename "$url" .git)"
    if [ -d "$PERSONAL_DIR/$name/.git" ]; then c_ok "repo $name"; continue; fi
    c_info "cloning $name"
    run mkdir -p "$PERSONAL_DIR"
    run git clone "$url" "$PERSONAL_DIR/$name"
  done
}

[ "$DRY_RUN" -eq 1 ] && c_info "dry run: nothing will be installed or changed"
step_xcode_tools
step_homebrew
step_oh_my_zsh
step_zshrc
step_node
step_repos
c_ok "bootstrap complete — open a new terminal"
