#!/usr/bin/env bash
set -euo pipefail

self=$0
start_dir="${ATTACH_ROOT:-$HOME/box}"

browse() {
  local d=$1 p base
  printf '../\n'
  fd --hidden --no-ignore --min-depth 1 --max-depth 1 \
     --exclude .git --exclude node_modules . "$d" 2>/dev/null \
  | while IFS= read -r p; do
      printf '%s\t%s\n' "$(/usr/bin/stat -f '%B' "${p%/}" 2>/dev/null || echo 0)" "$p"
    done \
  | sort -rn | cut -f2- \
  | while IFS= read -r p; do
      case $p in
        */) base=${p%/}; printf '%s/\n' "${base##*/}" ;;
        *)  printf '%s\n' "${p##*/}" ;;
      esac
    done
}

go() {
  local state=$1 nd=$2
  printf '%s\n' "$nd" > "$state"
  printf 'change-prompt(%s/ )+clear-query+reload(%q --browse %q)\n' "${nd##*/}" "$self" "$nd"
}

case ${1:-} in
  --browse) browse "${2:-$start_dir}"; exit 0 ;;
  --nav)
    cur=$(cat "$2")
    case $3 in
      ../) go "$2" "$(dirname "$cur")" ;;
      */)  go "$2" "$cur/${3%/}" ;;
      *)   printf 'accept\n' ;;
    esac
    exit 0 ;;
  --up) go "$2" "$(dirname "$(cat "$2")")"; exit 0 ;;
  --prev)
    cur=$(cat "$2")
    case $3 in
      ../) ls -Ap "$(dirname "$cur")" 2>/dev/null | head -40 || true ;;
      */)  ls -Ap "$cur/${3%/}" 2>/dev/null | head -40 || true ;;
      *)   file -b "$cur/$3" 2>/dev/null || true
           if command -v sips >/dev/null 2>&1; then
             sips -g pixelWidth -g pixelHeight "$cur/$3" 2>/dev/null | sed -n '2,3p' || true
           fi ;;
    esac
    exit 0 ;;
esac

target_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
[ -n "$target_pane" ] || { tmux display-message "attach-file: no target pane"; exit 0; }
for bin in fzf fd; do
  command -v "$bin" >/dev/null 2>&1 || { tmux display-message "attach-file: $bin not found"; exit 0; }
done
[ -d "$start_dir" ] || start_dir=$PWD

state=$(mktemp)
trap 'rm -f "$state"' EXIT
printf '%s\n' "$start_dir" > "$state"

selection=$(browse "$start_dir" | fzf --multi --reverse --border \
  --prompt="${start_dir##*/}/ " --header='Enter open/attach   ^h up   Tab mark   Esc cancel' \
  --bind "enter:transform:$self --nav $state {}" \
  --bind "ctrl-h:transform:$self --up $state" \
  --preview="$self --prev $state {}" --preview-window='down,8,wrap') || exit 0
[ -n "$selection" ] || exit 0

dir=$(cat "$state")
while IFS= read -r name; do
  [ -n "$name" ] || continue
  tmux set-buffer -b agent-attach -- "$dir/$name"
  tmux paste-buffer -b agent-attach -d -p -t "$target_pane"
  tmux send-keys -t "$target_pane" Space
done <<< "$selection"
