#!/usr/bin/env bash
set -euo pipefail
subject=$(head -n 1 "$1")
pattern='^(feat|fix|docs|style|refactor|test|chore|ci|perf|revert)(\((proof|runtime|bridge|contracts|protocol|ui|indexer|docs|ci|deps|security|repo)\))?(!)?: [a-zA-Z][-a-zA-Z0-9 .,():+/]+$'
if [[ ! "$subject" =~ $pattern ]]; then
  echo "Use type(scope): description, for example fix(bridge): reject replayed claims" >&2
  exit 1
fi
