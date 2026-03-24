#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <right|down> <path> [line]" >&2
  exit 1
fi

direction="$1"
target_path="$2"
line_number="${3:-}"

case "$direction" in
  right|vertical)
    split_flag='-h'
    ;;
  down|horizontal)
    split_flag='-v'
    ;;
  *)
    echo "unsupported split direction: $direction" >&2
    exit 1
    ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [[ "$target_path" = /* ]]; then
  file_path="$target_path"
else
  file_path="$repo_root/$target_path"
fi

line_arg=''
if [[ -n "$line_number" ]]; then
  case "$line_number" in
    ''|*[!0-9]*)
      echo "unsupported line number: $line_number" >&2
      exit 1
      ;;
    *)
      line_arg="+$line_number"
      ;;
  esac
fi

if [ -n "${TMUX:-}" ]; then
  launch_cmd='exec nvim'
  if [ -n "$line_arg" ]; then
    launch_cmd="$launch_cmd $(printf '%q' "$line_arg")"
  fi
  launch_cmd="$launch_cmd -- $(printf '%q' "$file_path")"
  tmux split-window "$split_flag" -c "$repo_root" "$launch_cmd" >/dev/null
  tmux select-layout -E >/dev/null
else
  if [ -n "$line_arg" ]; then
    exec nvim "$line_arg" -- "$file_path"
  else
    exec nvim -- "$file_path"
  fi
fi
