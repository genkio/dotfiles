#!/usr/bin/env bash
set -euo pipefail

self=$0
limit=${ATTACH_PHOTO_LIMIT:-500}
lib=${ATTACH_PHOTO_LIBRARY:-$HOME/Pictures/Photos Library.photoslibrary}
cache=${ATTACH_PHOTO_DIR:-$HOME/.cache/tmux-photo}
db="file:$lib/database/Photos.sqlite?mode=ro"
tab=$(printf '\t')

sql="
select
  a.ZUUID,
  a.ZDIRECTORY || '/' || a.ZFILENAME,
  coalesce(nullif(aa.ZORIGINALFILENAME, ''), a.ZFILENAME),
  strftime('%Y-%m-%d %H:%M', a.ZDATECREATED + 978307200, 'unixepoch', 'localtime'),
  coalesce(a.ZWIDTH, 0) || 'x' || coalesce(a.ZHEIGHT, 0),
  coalesce(a.ZFAVORITE, 0)
from ZASSET a
left join ZADDITIONALASSETATTRIBUTES aa on aa.ZASSET = a.Z_PK
where a.ZTRASHEDSTATE = 0 and a.ZVISIBILITYSTATE = 0 and a.ZKIND = 0
order by a.ZDATECREATED desc
limit $limit
"

derivative() {
  local u=$1 d=${1:0:1} cand sz best='' bestsz=0
  for cand in "$lib/resources/derivatives/$d/$u"_*.jpeg \
              "$lib/resources/derivatives/masters/$d/$u"_*.jpeg \
              "$lib/resources/renders/$d/$u"_*.jpeg; do
    [ -f "$cand" ] || continue
    sz=$(/usr/bin/stat -f '%z' "$cand" 2>/dev/null || echo 0)
    if [ "$sz" -gt "$bestsz" ]; then bestsz=$sz; best=$cand; fi
  done
  printf '%s\n' "$best"
}

safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

fetch_original() {
  local uuid=$1 dest=$2 id out
  for id in "$uuid/L0/001" "$uuid"; do
    rm -rf "$dest"; mkdir -p "$dest"
    if perl -e 'alarm shift; exec @ARGV' 90 \
         osascript \
           -e 'on run argv' \
           -e 'tell application "Photos" to export {media item id (item 1 of argv)} to (POSIX file (item 2 of argv) as alias) with using originals' \
           -e 'end run' \
           -- "$id" "$dest" >/dev/null 2>&1
    then
      out=$(find "$dest" -type f ! -name '.*' 2>/dev/null | head -1 || true)
      [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi
  done
  return 1
}

materialize() {
  local src=$1 name=$2 uuid=$3 stem ext out
  stem=$(safe "${name%.*}")-${uuid:0:8}
  ext=$(printf '%s' "${src##*.}" | tr 'A-Z' 'a-z')
  case $ext in
    jpg|jpeg|png|gif|webp)
      out="$cache/$stem.$ext"
      [ -s "$out" ] || cp -f "$src" "$out" || return 1
      ;;
    *)
      out="$cache/$stem.jpg"
      [ -s "$out" ] ||
        sips -s format jpeg -s formatOptions 90 "$src" --out "$out" >/dev/null 2>&1 ||
        return 1
      ;;
  esac
  [ -s "$out" ] || return 1
  printf '%s\n' "$out"
}

resolve() {
  local uuid=$1 orig=$2 name=$3 fetch=${4:-} src='' file
  mkdir -p "$cache"
  if [ "$fetch" = fetch ]; then
    src=$(fetch_original "$uuid" "$cache/fetch-$$" || true)
    [ -n "$src" ] || printf '%s: Photos export failed, used the local copy. ' "$name" >&2
  fi
  [ -n "$src" ] || { [ -f "$orig" ] && src=$orig; }
  [ -n "$src" ] || src=$(derivative "$uuid")
  if [ ! -f "$src" ]; then
    printf '%s: no local pixels. ' "$name" >&2
    rm -rf "$cache/fetch-$$"
    return 1
  fi
  file=$(materialize "$src" "$name" "$uuid") || {
    printf '%s: could not convert to jpeg. ' "$name" >&2
    rm -rf "$cache/fetch-$$"
    return 1
  }
  rm -rf "$cache/fetch-$$"
  printf '%s\n' "$file"
}

case ${1:-} in
  --list)
    sqlite3 -separator "$tab" "$db" "$sql" |
    while IFS="$tab" read -r uuid rel name created dims fav; do
      [ -n "$uuid" ] || continue
      orig="$lib/originals/$rel"
      marks=''
      [ "$fav" = 1 ] && marks='★'
      [ -f "$orig" ] || marks="${marks}☁"
      printf '%s  %-24s %11s %-3s\t%s\t%s\t%s\t%s\n' \
        "$created" "${name:0:24}" "$dims" "$marks" "$uuid" "$orig" "$name" "$dims"
    done
    exit 0 ;;
  --prev)
    uuid=${2:-}; orig=${3:-}; name=${4:-}; full=${5:-}
    img=$(derivative "$uuid")
    if [ ! -f "$img" ]; then
      case $(printf '%s' "${orig##*.}" | tr 'A-Z' 'a-z') in
        jpg|jpeg|png|gif|webp) img=$orig ;;
        *) img='' ;;
      esac
    fi
    cols=${FZF_PREVIEW_COLUMNS:-60}
    rows=$(( ${FZF_PREVIEW_LINES:-20} - 4 ))
    [ "$rows" -ge 2 ] || rows=2

    dims=''
    [ ! -f "$img" ] ||
      dims=$(sips -g pixelWidth -g pixelHeight "$img" 2>/dev/null |
             awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if (w && h) print w, h}')

    if [ -f "$orig" ]; then
      src="original $full"
    elif [ "${dims// /x}" = "$full" ]; then
      src="derivative $full   (full size)"
    elif [ -n "$dims" ]; then
      src="derivative ${dims// /x}   (original $full not on this mac)"
    else
      src="nothing local (original $full)"
    fi
    printf '%s\n%s\n\n' "$name" "$src"

    if [ -f "$img" ]; then
      fit=(-h "$rows")
      if [ -n "$dims" ]; then
        iw=${dims%% *}; ih=${dims##* }
        [ "$(( iw * rows * 2 ))" -le "$(( ih * cols ))" ] || fit=(-w "$cols")
      fi
      viu -b -s "${fit[@]}" -- "$img" 2>/dev/null ||
        printf 'viu could not render %s\n' "${img##*/}"
    else
      printf 'no local pixels for this asset\n'
    fi
    exit 0 ;;
  --resolve)
    resolve "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    exit $? ;;
esac

target_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
[ -n "$target_pane" ] || { tmux display-message "attach-photo: no target pane"; exit 0; }
for bin in fzf viu sqlite3; do
  command -v "$bin" >/dev/null 2>&1 || { tmux display-message "attach-photo: $bin not found"; exit 0; }
done
[ -d "$lib" ] || { tmux display-message "attach-photo: no library at $lib"; exit 0; }
sqlite3 "$db" 'select 1 from ZASSET limit 1' >/dev/null 2>&1 ||
  { tmux display-message "attach-photo: cannot read the library db (Full Disk Access?)"; exit 0; }

out=$("$self" --list | fzf --multi --reverse --border \
  --delimiter="$tab" --with-nth=1 \
  --prompt='photos > ' \
  --header='Enter attach   ^o get the original   Tab mark   ☁ not local' \
  --expect=ctrl-o \
  --preview="$self --prev {2} {3} {4} {5}" \
  --preview-window='right,55%,border-left') || exit 0

key=$(printf '%s\n' "$out" | head -1)
picks=$(printf '%s\n' "$out" | tail -n +2)
[ -n "$picks" ] || exit 0
[ "$key" != ctrl-o ] || fetch=fetch

mkdir -p "$cache"
find "$cache" -type f -mtime +7 -delete 2>/dev/null || true

notes=''
while IFS="$tab" read -r _ uuid orig name _; do
  [ -n "${uuid:-}" ] || continue
  [ "$key" != ctrl-o ] || tmux display-message -d 1000 "attach-photo: asking Photos for $name..."
  err=$(mktemp)
  file=$(resolve "$uuid" "$orig" "$name" "${fetch:-}" 2>"$err" || true)
  notes="$notes$(cat "$err")"
  rm -f "$err"
  [ -n "$file" ] || continue

  tmux set-buffer -b photo-attach -- "$file"
  tmux paste-buffer -b photo-attach -d -p -t "$target_pane"
  tmux send-keys -t "$target_pane" Space
done <<< "$picks"

[ -z "$notes" ] || tmux display-message -d 4000 "attach-photo: $notes"
