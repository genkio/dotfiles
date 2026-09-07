#!/usr/bin/env bash
set -euo pipefail

# Browse the macOS Photos library with fzf and paste the chosen photo into the
# agent pane, the way attach-file.sh does for the filesystem. Run inside
# `display-popup -E` by `prefix + P` (see .tmux.conf).
#
# There is no picker to call and no folder to walk: a Photos library is a
# bundle keyed by a Core Data sqlite db, so the listing comes from a read-only
# query of that db and the pixels come from paths built out of the asset UUID.
# Reading the db needs Full Disk Access for the terminal (System Settings >
# Privacy & Security), which is also what lets the originals be read.
#
# mode=ro, not immutable=1: the library runs in WAL mode with megabytes of
# uncommitted -wal, and immutable=1 ignores it - i.e. the screenshot you took a
# minute ago, the single most likely thing to want here, would be missing.
#
# Previews go through viu in block mode, same as the yazi plugin: Alacritty has
# no graphics protocol, and -b keeps viu from probing the terminal for one
# (a probe never gets its reply through a popup overlay).
#
# With iCloud "Optimize Mac Storage" the original may not be on this mac. Those
# rows are marked ☁; Enter still attaches the largest local derivative, which
# is often full resolution but sometimes only a 480px thumbnail, so ^o asks
# Photos.app to fetch the real original first.
#
# Sub-commands (--list, --prev, --resolve) exist because fzf re-enters this
# script for the listing and for every preview; --resolve prints what Enter
# would attach without pasting it, which is the way to debug this by hand.

self=$0
limit=${ATTACH_PHOTO_LIMIT:-500}
lib=${ATTACH_PHOTO_LIBRARY:-$HOME/Pictures/Photos Library.photoslibrary}
cache=${ATTACH_PHOTO_DIR:-$HOME/.cache/tmux-photo}
# 'file:' with a bare absolute path, not 'file://': the double slash would make
# the first path component an authority and the open would fail.
db="file:$lib/database/Photos.sqlite?mode=ro"
tab=$(printf '\t')

# Core Data keeps dates in seconds since 2001-01-01; +978307200 shifts them to
# the unix epoch. TRASHEDSTATE/VISIBILITYSTATE drop Recently Deleted and the
# non-primary frames of bursts and the like, KIND=0 drops videos (no agent
# takes one as an attachment).
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

# The largest jpeg the library already has for this asset, or nothing. Photos
# spreads them over three trees whose suffixes change between macOS releases
# (_1_105_c, _1_102_o, _4_5005_c, _1_201_a for an edited render), so pick by
# byte size rather than guess a name: biggest file, best pixels.
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

# Photos names an export after the original filename, which can hold spaces,
# and the agent's attach detection reads a bare pasted path - so every name
# gets flattened before anything lands in the cache.
safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

# Ask Photos.app for the true original, which is what pulls it back from
# iCloud. Exports into an empty dir so the one file that lands there is the
# answer, whatever Photos decides to call it. The first run raises a one-time
# "control Photos" prompt and launches Photos if it is not running; a refusal
# or a stalled download falls through to the derivative. Photos ids are
# '<uuid>/L0/001' on current versions and bare uuids on older ones, so try
# both. perl's alarm stands in for timeout(1), which macOS does not ship.
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

# Copy (or convert) the chosen bytes into the cache under a clean name. Always
# a copy, never the library path itself: the bundle path holds a space, which
# the bare-path paste cannot carry, and an agent has no business reading inside
# the library. HEIC and the raw/tiff imports go through sips because no agent
# and no previewer here reads them.
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

# Path to attach on stdout, one line of explanation on stderr when the result
# is not what was asked for.
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
      # One stat per row, no subprocess: cheap over the whole listing, and the
      # only honest way to show what Enter would really attach.
      # Braces are load-bearing - bash reads the high bytes of ☁ as more of
      # the name and dies on an unbound 'marks☁' without them.
      [ -f "$orig" ] || marks="${marks}☁"
      printf '%s  %-24s %11s %-3s\t%s\t%s\t%s\t%s\n' \
        "$created" "${name:0:24}" "$dims" "$marks" "$uuid" "$orig" "$name" "$dims"
    done
    exit 0 ;;
  --prev)
    uuid=${2:-}; orig=${3:-}; name=${4:-}; full=${5:-}
    # Preview off the derivative even when the original is here: it is a small
    # jpeg, so it renders instantly and sidesteps viu's lack of HEIC support.
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

    # The second line is about what Enter would attach, not about what is being
    # rendered: with two thirds of the library offloaded to iCloud, and half of
    # those left with nothing but a 480px thumbnail, the pixel count you are
    # about to hand an agent is the one thing worth saying out loud.
    if [ -f "$orig" ]; then
      src="original $full"
    elif [ "${dims// /x}" = "$full" ]; then
      # Same pixels as the original, so ^o would only re-download what is
      # already here - worth saying, since two thirds of the rows are ☁.
      src="derivative $full   (full size)"
    elif [ -n "$dims" ]; then
      src="derivative ${dims// /x}   (original $full not on this mac)"
    else
      src="nothing local (original $full)"
    fi
    printf '%s\n%s\n\n' "$name" "$src"

    if [ -f "$img" ]; then
      # One dimension only. Given both, viu stretches the image to exactly that
      # box instead of fitting inside it, so pass whichever one the photo is
      # actually bound by and let viu derive the other. A half-block cell is
      # two pixels tall, hence the 2 in the comparison.
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

# display-popup leaves #{pane_id} empty in its shell-command and $TMUX_PANE is
# the popup's own pane, so resolve the underlying active pane with a fresh
# query, which ignores the overlay (same as attach-file.sh).
target_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
[ -n "$target_pane" ] || { tmux display-message "attach-photo: no target pane"; exit 0; }
for bin in fzf viu sqlite3; do
  command -v "$bin" >/dev/null 2>&1 || { tmux display-message "attach-photo: $bin not found"; exit 0; }
done
[ -d "$lib" ] || { tmux display-message "attach-photo: no library at $lib"; exit 0; }
sqlite3 "$db" 'select 1 from ZASSET limit 1' >/dev/null 2>&1 ||
  { tmux display-message "attach-photo: cannot read the library db (Full Disk Access?)"; exit 0; }

# --expect, not a second key binding: ^o goes down the same accept path, only
# with the iCloud fetch turned on.
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

  # Bracketed paste (-p) of the bare path alone, like a clipboard paste, so the
  # CLI's image-path detection fires on a clean path. Trailing Space is a
  # separate keystroke so detection sees only the path (same as attach-file.sh).
  tmux set-buffer -b photo-attach -- "$file"
  tmux paste-buffer -b photo-attach -d -p -t "$target_pane"
  tmux send-keys -t "$target_pane" Space
done <<< "$picks"

[ -z "$notes" ] || tmux display-message -d 4000 "attach-photo: $notes"
