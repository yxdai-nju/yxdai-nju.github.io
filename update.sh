#!/bin/bash
set -eux

git checkout --orphan latest_branch
git add -A
git commit -S -s -m "Squash history as of $(date +%Y-%m-%d)"
git branch -D main
git branch -m main
git push -f origin main
