#!/bin/zsh
source  ~/.zshrc
PROJECTS="${PROJECTS:-$HOME/Documents/projects}"
FILENAME=$1
BASE="$PROJECTS/tmp"
touch "$BASE/$FILENAME"
code "$BASE/$FILENAME"
