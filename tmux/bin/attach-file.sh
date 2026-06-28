#!/usr/bin/env bash
set -euo pipefail

# Browse files with fzf and paste the chosen path into the agent pane (Claude
# Code / Codex). Both CLIs attach an image from a bare path pasted into the
# prompt, so this is drag-and-drop without the mouse or clipboard. Run inside
# `display-popup -E` by `prefix + a` (see .tmux.conf). fzf, not yazi: yazi's
# startup terminal probe never gets a reply through a popup overlay and wedges
# the server (yazi#2308); fzf needs no such probe.
#
# fzf can't keep state across reloads, so the current dir lives in a temp file
# and the navigation/preview logic is re-entered as the sub-commands below,
# which fzf key-bindings call on every move.

self=$0
start_dir="${ATTACH_ROOT:-$HOME/box}"

# One directory's entries, newest first (creation time, BSD stat), basenames
# only since the caller tracks the dir. Dirs get a trailing / so navigation can
# tell them from files; '../' leaves the dir. --hidden --no-ignore so it shows
# everything a file manager would, minus the obvious noise. Per-file stat (not
# xargs) so an empty dir can't trip pipefail and abort under set -e.
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
      # fd suffixes dirs with /; that slash flags a dir for nav, but must be
      # stripped or the basename comes out empty.
      case $p in
        */) base=${p%/}; printf '%s/\n' "${base##*/}" ;;
        *)  printf '%s\n' "${p##*/}" ;;
      esac
    done
}

# clear-query so the old filter doesn't hide the new listing after navigating.
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

# display-popup leaves #{pane_id} empty in its shell-command, and $TMUX_PANE is
# the popup's own pane, so resolve the underlying active pane with a fresh
# query (it ignores the overlay). Verified on tmux 3.6.
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
  # Bracketed paste (-p) of the raw path alone, like a clipboard paste, so the
  # CLI's image-path detection fires on a clean path. Trailing Space is a
  # separate keystroke so detection sees only the path; drop it if an agent
  # fails to register the attachment.
  tmux set-buffer -b agent-attach -- "$dir/$name"
  tmux paste-buffer -b agent-attach -d -p -t "$target_pane"
  tmux send-keys -t "$target_pane" Space
done <<< "$selection"
