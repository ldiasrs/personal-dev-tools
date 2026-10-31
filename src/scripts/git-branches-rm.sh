#!/usr/bin/env bash

DELETE_FLAG="-d"
for arg in "$@"; do
  case "$arg" in
    --force)
      DELETE_FLAG="-D"
      shift
      ;;
  esac
done

git branch | egrep -v "(^\*|master|main|dev|skip_branch_name|learning-new-asyncresult|feature/sc-7741)|feature/intlen-1773-stips-temenos" | xargs git branch $DELETE_FLAG
