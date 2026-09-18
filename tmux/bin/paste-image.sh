#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
dumper=${CLIP_PNG:-$here/clip-png.sh}
cache=${CLIP_PASTE_DIR:-$HOME/.cache/tmux-clip}

pane=${1:-}
[ -n "$pane" ] || { tmux display-message -d 3000 "paste-image: no target pane"; exit 0; }

fail() { rm -f "${out:-}"; tmux display-message -d 3000 "paste-image: $1"; exit 0; }

peer_user() {
  local host=$1 pair
  for pair in $(tmux show-option -gqv @clip_ssh_users); do
    case $pair in
      "$host"=*) printf '%s\n' "${pair#*=}"; return 0 ;;
    esac
  done
  printf '%s\n' "$USER"
}

session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null || true)
[ -n "$session" ] || fail "pane $pane is gone"

client=$(tmux show-environment -t "$session" SSH_CLIENT 2>/dev/null |
         sed -n 's/^SSH_CLIENT=//p' | awk '{print $1}')

mkdir -p "$cache"
out="$cache/clip-$(date +%Y%m%d-%H%M%S).png"

if [ -z "$client" ]; then
  "$dumper" > "$out" 2>/dev/null || fail "clipboard holds no image"
else
  node=$(tailscale whois "$client" 2>/dev/null |
         sed -n 's/^ *Name: *\([^. ]*\).*/\1/p' | head -1)
  target="$(peer_user "$node")@$client"
  err=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
            "$target" 'bash -s' <"$dumper" 2>&1 >"$out" | tr '\n' ' ') ||
    fail "$target: ${err:-ssh failed}"
fi

[ -s "$out" ] || { rm -f "$out"; fail "clipboard holds no image"; }

find "$cache" -name 'clip-*.png' -type f -mtime +7 -delete 2>/dev/null || true

tmux set-buffer -b clip-attach -- "$out"
tmux paste-buffer -b clip-attach -d -p -t "$pane"
tmux send-keys -t "$pane" Space
