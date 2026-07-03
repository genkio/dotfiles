#!/usr/bin/env bash
set -euo pipefail

# Use a remote tailscale exit node from this mac (brew tailscaled variant).
#
# tailscaled's darwin router never programs the IPv4 default route when an
# exit node is selected (the GUI app does it via NetworkExtension), so
# `tailscale set --exit-node=X` alone routes nothing. Fix is three routes:
#   0.0.0.0/1 + 128.0.0.0/1 via the tailscale utun  -> beat the default route
#   interface-scoped default via the physical gw    -> tailscaled binds its own
#     sockets to the physical interface (IP_BOUND_IF); without a scoped default
#     those sockets resolve to the utun, mismatch, and the tunnel collapses
#     with "sendto: network is unreachable".
#
# Routes are flushed by macOS on network change/sleep/reboot: rerun `on`.
# DNS still uses the local network's resolver (lookups leak around the exit
# node; the IP traffic itself goes through it). LAN stays reachable.
#
# Daily use:
#   tailscale-exit.sh on office   # any node offering an exit node
#   tailscale-exit.sh off
#   tailscale-exit.sh status

usage() {
  echo "Usage: $(basename "$0") on <node> | off | status" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
cmd="$1"
node="${2:-}"
[[ "$cmd" == "on" && -z "$node" ]] && usage

if [[ "$cmd" != "status" && "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

ts_if() { route -n get 100.100.100.100 2>/dev/null | awk '/interface:/{print $2}'; }
def_gw() { route -n get default 2>/dev/null | awk '/gateway:/{print $2}'; }
def_if() { route -n get default 2>/dev/null | awk '/interface:/{print $2}'; }

del_routes() {
  route -q delete -inet 0.0.0.0/1 >/dev/null 2>&1 || true
  route -q delete -inet 128.0.0.0/1 >/dev/null 2>&1 || true
  local ifc
  ifc="$(def_if)"
  [[ -n "$ifc" ]] && route -q delete -inet default -ifscope "$ifc" >/dev/null 2>&1 || true
}

public_org() { curl -s --max-time 12 ipinfo.io/org || true; }

case "$cmd" in
  on)
    tailscale set --exit-node="$node"
    tsif="$(ts_if)"
    gw="$(def_gw)"
    ifc="$(def_if)"
    if [[ -z "$tsif" || -z "$gw" || -z "$ifc" ]]; then
      echo "Error: could not detect routes (tsif=$tsif gw=$gw if=$ifc)" >&2
      exit 1
    fi
    del_routes
    route -q add -inet 0.0.0.0/1 -interface "$tsif"
    route -q add -inet 128.0.0.0/1 -interface "$tsif"
    route -q add -inet default "$gw" -ifscope "$ifc"
    org="$(public_org)"
    if [[ -z "$org" ]]; then
      del_routes
      tailscale set --exit-node=
      echo "Error: no internet through exit node, reverted." >&2
      exit 1
    fi
    echo "exit node $node active, public org: $org"
    ;;
  off)
    del_routes
    tailscale set --exit-node=
    echo "exit node off, public org: $(public_org)"
    ;;
  status)
    tailscale status | grep 'exit node' || echo "no exit node peers"
    netstat -rn -f inet | awk '$1 == "default" || $1 == "0/1" || $1 == "128.0/1" {print $1, $2, $NF}'
    echo "public org: $(public_org)"
    ;;
  *)
    usage
    ;;
esac
