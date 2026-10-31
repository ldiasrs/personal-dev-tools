# Usar essa opcao em um PR que esta com conflito e voce quer forcar o rebase do seu branch
# incoming changes são o que estão no meu branch atual
# current changes são o que estão no branch main/base
mode=$1 #forcemybranch =  git rebase -X theirs origin/main

shopt -s nocasematch

# check if mode is passed and if not print usage and exit
if [ -z $mode ]; then
  echo "Usage: rebase-main.sh <mode>"
  echo "Mode: stash, normal, forcemybranch"
  exit 1
fi

if [ $mode == "stash" ]; then
  echo "Rebase mode STACHING"
  git stash
  git status
  git fetch origin main 
  git rebase origin/main
  git stash pop
    echo "DONE!!"
  exit 1
fi

git status
git fetch origin main 

if [ $mode == "forcemybranch" ]; then
  echo "Forcing current branch  with command: git rebase -X theirs origin/main"
  git rebase -X theirs origin/main
  exit 1
fi

if [ $mode == "normal" ]; then
  echo "Normal rebase"
  git rebase origin/main
  exit 1
fi
