#!/usr/bin/env bash
set -euo pipefail

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

def_gw() {
  netstat -rn -f inet | awk '$1 == "default" && $2 ~ /^[0-9]/ {if ($3 !~ /I/) {print $2; exit} if (!s) s=$2} END {if (s) print s}' | head -1
}
def_if() {
  netstat -rn -f inet | awk '$1 == "default" && $2 ~ /^[0-9]/ {if ($3 !~ /I/) {print $NF; exit} if (!s) s=$NF} END {if (s) print s}' | head -1
}

has_default() { netstat -rn -f inet | awk '$1 == "default" && $3 !~ /I/ {found=1} END {exit !found}'; }

del_slash1s() {
  route -q delete -inet 0.0.0.0/1 >/dev/null 2>&1 || true
  route -q delete -inet 128.0.0.0/1 >/dev/null 2>&1 || true
}

del_scoped_defaults() {
  netstat -rn -f inet | awk '$1 == "default" && $3 ~ /I/ {print $NF}' | while read -r ifc; do
    route -q delete -inet default -ifscope "$ifc" >/dev/null 2>&1 || true
  done
}

restore_default() {
  local gw="$1"
  has_default && return 0
  [[ -n "$gw" ]] && route -q add -inet default "$gw" >/dev/null 2>&1 || true
}

ensure_default() {
  local gw="$1" ifc="$2" i
  for i in 1 2 3; do
    restore_default "$gw"
    has_default && return 0
    sleep 1
  done
  echo "default route not sticking, re-running DHCP on ${ifc}..." >&2
  [[ -n "$ifc" ]] && ipconfig set "$ifc" DHCP >/dev/null 2>&1 || true
  for i in $(seq 10); do
    has_default && return 0
    sleep 1
  done
  return 1
}

public_org() { curl -s --max-time 12 ipinfo.io/org || true; }

case "$cmd" in
  on)
    gw="$(def_gw)"
    del_slash1s
    del_scoped_defaults
    restore_default "$gw"
    tsif="$(ts_if)"
    gw="$(def_gw)"
    ifc="$(def_if)"
    if [[ -z "$tsif" || -z "$gw" || -z "$ifc" ]]; then
      echo "Error: no usable network or tailscale interface (tsif=$tsif gw=$gw if=$ifc)" >&2
      exit 1
    fi
    tailscale set --exit-node="$node"
    route -q add -inet 0.0.0.0/1 -interface "$tsif"
    route -q add -inet 128.0.0.0/1 -interface "$tsif"
    route -q add -inet default "$gw" -ifscope "$ifc"
    org="$(public_org)"
    if [[ -z "$org" ]]; then
      tailscale set --exit-node=
      del_slash1s
      del_scoped_defaults
      ensure_default "$gw" "$ifc" || true
      echo "Error: no internet through exit node, reverted." >&2
      exit 1
    fi
    echo "exit node $node active, public org: $org"
    ;;
  off)
    gw="$(def_gw)"
    ifc="$(def_if)"
    tailscale set --exit-node=
    del_slash1s
    del_scoped_defaults
    if ! ensure_default "$gw" "$ifc"; then
      echo "Warning: exit node off but no default route; table:" >&2
      netstat -rn -f inet | awk '$1 == "default" {print $1, $2, $3, $NF}' >&2
      exit 1
    fi
    org="$(public_org)"
    if [[ -z "$org" ]]; then
      echo "Warning: exit node off but no internet; check route table:" >&2
      netstat -rn -f inet | awk '$1 == "default" {print $1, $2, $3, $NF}' >&2
      exit 1
    fi
    echo "exit node off, public org: $org"
    ;;
  status)
    tailscale status | grep 'exit node' || echo "no exit node peers"
    netstat -rn -f inet | awk '$1 == "default" || $1 == "0/1" || $1 == "128.0/1" {print $1, $2, $3, $NF}'
    if tailscale status | grep -q 'active; exit node' && ! netstat -rn -f inet | grep -q '^0/1'; then
      echo "WARNING: exit node set but routes missing (network changed?), rerun: $(basename "$0") on <node>"
    fi
    echo "public org: $(public_org)"
    ;;
  *)
    usage
    ;;
esac
