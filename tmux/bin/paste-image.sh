#!/usr/bin/env bash
set -euo pipefail

# prefix + V: attach the clipboard image to the agent pane, including when that
# pane is on a machine you are ssh'd into (see .tmux.conf).
#
# Claude Code / Codex read the image from the pasteboard of the host the process
# runs on, and an ssh pty can only carry text (bracketed paste, OSC 52), so a
# remote C-v can never see the mac you are sitting at. The bytes have to travel
# out of band: this pulls them over the tailnet instead, then pastes the local
# path like attach-file.sh does.
#
# Pull, not push: the pane knows who is attached to it ($SSH_CLIENT, kept fresh
# by update-environment in .tmux.conf), so nothing is needed on the other end -
# no hotkey, no agent, not even this checkout (clip-png.sh goes over as stdin).

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
dumper=${CLIP_PNG:-$here/clip-png.sh}
cache=${CLIP_PASTE_DIR:-$HOME/.cache/tmux-clip}

pane=${1:-}
[ -n "$pane" ] || { tmux display-message -d 3000 "paste-image: no target pane"; exit 0; }

# out may already exist as an empty file: the redirect below creates it before
# the dumper decides there is no image.
fail() { rm -f "${out:-}"; tmux display-message -d 3000 "paste-image: $1"; exit 0; }

# Peer account names, from the tmux option so this map stays machine-agnostic
# (the two macs use different local users and ssh cannot learn the origin's
# username from SSH_CLIENT). Format: 'host=user host=user'.
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

# Unset prints '-SSH_CLIENT', so the match on 'SSH_CLIENT=' is the local case.
client=$(tmux show-environment -t "$session" SSH_CLIENT 2>/dev/null |
         sed -n 's/^SSH_CLIENT=//p' | awk '{print $1}')

mkdir -p "$cache"
out="$cache/clip-$(date +%Y%m%d-%H%M%S).png"

if [ -z "$client" ]; then
  "$dumper" > "$out" 2>/dev/null || fail "clipboard holds no image"
else
  # whois resolves the tailnet IP to the node name that keys the user map; a
  # non-tailnet client (LAN) just falls through to $USER on the bare IP.
  node=$(tailscale whois "$client" 2>/dev/null |
         sed -n 's/^ *Name: *\([^. ]*\).*/\1/p' | head -1)
  target="$(peer_user "$node")@$client"
  # The dumper goes over as stdin rather than being run by path, so only the
  # machine holding this binding needs an up-to-date checkout.
  # accept-new, not the default ask: run-shell has no tty to answer the
  # first-contact prompt on, and the tailnet already authenticates the peer.
  # display-message shows one line, and ssh's refusals are multi-line.
  err=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
            "$target" 'bash -s' <"$dumper" 2>&1 >"$out" | tr '\n' ' ') ||
    fail "$target: ${err:-ssh failed}"
fi

[ -s "$out" ] || { rm -f "$out"; fail "clipboard holds no image"; }

find "$cache" -name 'clip-*.png' -type f -mtime +7 -delete 2>/dev/null || true

# Bracketed paste of the bare path, then Space as a separate keystroke, so the
# agent's image-path detection sees a clean path (same as attach-file.sh).
tmux set-buffer -b clip-attach -- "$out"
tmux paste-buffer -b clip-attach -d -p -t "$pane"
tmux send-keys -t "$pane" Space
