#!/usr/bin/env bash
set -euo pipefail

self=$0
. "${0%/*}/attach-lib.sh"
start_dir="${ATTACH_ROOT:-$HOME}"

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

preview() {
  local f=$1 cols=${FZF_PREVIEW_COLUMNS:-60} rows=${FZF_PREVIEW_LINES:-20} img='' dims iw ih fit
  printf '%s\n%s\n\n' "${f##*/}" "$(file -b "$f" 2>/dev/null | head -1 || true)"
  rows=$(( rows - 3 ))
  [ "$rows" -ge 2 ] || rows=2

  case $(printf '%s' "${f##*.}" | tr 'A-Z' 'a-z') in
    jpg|jpeg|png|gif|webp|bmp) img=$f ;;
    heic|heif|tif|tiff)
      # viu can't decode these
      img="${TMPDIR:-/tmp}/attach-file-preview.jpg"
      sips -s format jpeg -Z 1600 "$f" --out "$img" >/dev/null 2>&1 || img='' ;;
  esac

  if [ -n "$img" ] && command -v viu >/dev/null 2>&1; then
    fit=(-h "$rows")
    dims=$(sips -g pixelWidth -g pixelHeight "$img" 2>/dev/null |
           awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if (w && h) print w, h}')
    if [ -n "$dims" ]; then
      iw=${dims%% *}; ih=${dims##* }
      [ "$(( iw * rows * 2 ))" -le "$(( ih * cols ))" ] || fit=(-w "$cols")
    fi
    viu -b -s "${fit[@]}" -- "$img" 2>/dev/null || printf 'viu could not render this image\n'
  elif [ ! -s "$f" ] || file -b --mime-encoding "$f" 2>/dev/null | grep -qv binary; then
    if command -v bat >/dev/null 2>&1; then
      bat --color=always --style=plain --paging=never --line-range=":$rows" -- "$f" 2>/dev/null || true
    else
      head -n "$rows" -- "$f" 2>/dev/null || true
    fi
  fi
}

go() {
  local state=$1 nd=$2
  printf '%s\n' "$nd" > "$state"
  printf 'change-prompt(%s/ )+change-border-label( %s/ )+clear-query+reload(%q --browse %q)\n' \
    "${nd##*/}" "${nd##*/}" "$self" "$nd"
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
  --rm)
    cur=$(cat "$2"); shift 2
    names=()
    for n in "$@"; do [ "$n" = ../ ] || names+=("${n%/}"); done
    [ "${#names[@]}" -gt 0 ] || exit 0
    printf 'Move to Trash from %s:\n' "$cur"
    printf '  %s\n' "${names[@]}"
    printf 'Confirm? [y/N] '
    read -r -n 1 ans < /dev/tty || ans=''
    printf '\n'
    [ "$ans" = y ] || [ "$ans" = Y ] || exit 0
    ( cd "$cur" && /usr/bin/trash -- "${names[@]}" ) ||
      { printf 'Press any key... '; read -r -n 1 _ < /dev/tty || true; }
    exit 0 ;;
  --up) go "$2" "$(dirname "$(cat "$2")")"; exit 0 ;;
  --prev)
    cur=$(cat "$2")
    case $3 in
      ../) ls -Ap "$(dirname "$cur")" 2>/dev/null | head -40 || true ;;
      */)  ls -Ap "$cur/${3%/}" 2>/dev/null | head -40 || true ;;
      *)   preview "$cur/$3" ;;
    esac
    exit 0 ;;
esac

target_pane=$(attach_target)
[ -n "$target_pane" ] || { attach_notify attach-file "no target pane"; exit 0; }
for bin in fzf fd; do
  command -v "$bin" >/dev/null 2>&1 || { attach_notify attach-file "$bin not found"; exit 0; }
done
[ -d "$start_dir" ] || start_dir=$(attach_cwd)

state=$(mktemp)
trap 'rm -f "$state"' EXIT
printf '%s\n' "$start_dir" > "$state"

selection=$(browse "$start_dir" | fzf --multi --reverse --border \
  --prompt="${start_dir##*/}/ " --border-label=" ${start_dir##*/}/ " \
  --header='j/k move   / search   Enter open/attach   ^h up   ^d trash   Tab mark   Esc cancel' \
  "${attach_fzf_nav[@]}" \
  --bind "enter:transform:$self --nav $state {}" \
  --bind 'load:hide-input+rebind(j,k,/)' \
  --bind "ctrl-h:transform:$self --up $state" \
  --bind "ctrl-d:execute($self --rm $state {+})+clear-selection+reload($self --browse \"\$(cat $state)\")" \
  --preview="$self --prev $state {}" --preview-window='right,55%,border-left') || exit 0
[ -n "$selection" ] || exit 0

dir=$(cat "$state")
while IFS= read -r name; do
  [ -n "$name" ] || continue
  attach_send "$target_pane" "$dir/$name"
done <<< "$selection"
