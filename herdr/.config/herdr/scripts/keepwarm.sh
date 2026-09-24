#!/bin/sh
# Keep a Claude pane's 1h prompt cache warm while idle, armed per pane on demand.
set -eu

# Ping after this many minutes without transcript activity; keep it under the 60m cache TTL.
ping_after_min=50
default_hours=8

herdr="${HERDR_BIN_PATH:-herdr}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-keepwarm"
interval=$(( ping_after_min * 60 ))
ttl=3600
ping_text="Reply with exactly: ok"

usage() {
  echo "usage: $(basename "$0") prompt|arm <pane> [8h|90m|2h30m]|disarm <pane>|check <pane>|status" >&2
  exit 2
}

notify() {
  "$herdr" notification show "keepwarm" --body "$1" --sound none >/dev/null 2>&1 || true
}

# Sidebar badge; the TTL clears it if the runner dies without cleaning up.
badge() {
  if [ -n "${2:-}" ]; then
    ttl_ms=$(( ($2 - $(date +%s) + 60) * 1000 ))
    [ "$ttl_ms" -le 86400000 ] || ttl_ms=86400000
    "$herdr" pane report-metadata "$1" --source keepwarm \
      --token "warm=warm $(date -r "$2" +%H:%M)" --ttl-ms "$ttl_ms" >/dev/null 2>&1 || true
  else
    "$herdr" pane report-metadata "$1" --source keepwarm --clear-token warm >/dev/null 2>&1 || true
  fi
}

pidfile() { printf '%s/%s.pid' "$state" "$(printf '%s' "$1" | tr ':/' '__')"; }

armed_pid() {
  f=$(pidfile "$1")
  [ -f "$f" ] || return 1
  pid=$(sed -n 1p "$f")
  if kill -0 "$pid" 2>/dev/null; then
    printf '%s' "$pid"
  else
    rm -f "$f"
    return 1
  fi
}

seconds() {
  case "$1" in
    *[!0-9hm]* | "" ) echo "bad duration: $1" >&2; exit 2 ;;
  esac
  h=$(printf '%s' "$1" | sed -n 's/^\([0-9]*\)h.*/\1/p')
  m=$(printf '%s' "$1" | sed -n 's/^\([0-9]*h\)\{0,1\}\([0-9]*\)m$/\2/p')
  s=$(( ${h:-0} * 3600 + ${m:-0} * 60 ))
  [ "$s" -gt 0 ] || { echo "bad duration: $1" >&2; exit 2; }
  echo "$s"
}

agent_field() {
  "$herdr" agent get "$1" 2>/dev/null | jq -r ".result.agent.$2 // empty"
}

last_turn() {
  ts=$(jq -r 'select(.type == "assistant") | .timestamp // empty' "$1" | tail -1)
  [ -n "$ts" ] && date -j -u -f '%Y-%m-%dT%H:%M:%S' "${ts%%.*}" +%s 2>/dev/null
}

# Check every herdr and transcript field the runner reads, so an upgrade fails loudly at arm time.
preflight() {
  fail() { echo "$pane: $1" >&2; [ -n "${quiet:-}" ] || notify "$pane: $1"; exit 1; }
  info=$("$herdr" agent get "$pane" 2>/dev/null) || fail "no agent"
  kind=$(printf '%s' "$info" | jq -r '.result.agent.agent // empty')
  session=$(printf '%s' "$info" | jq -r '.result.agent.agent_session.value // empty')
  cwd=$(printf '%s' "$info" | jq -r '.result.agent.cwd // empty')
  agent_status=$(printf '%s' "$info" | jq -r '.result.agent.agent_status // empty')
  [ "$kind" = claude ] || fail "not a claude pane (agent '$kind')"
  [ -n "$session" ] || fail "herdr reports no session id"
  [ -d "$cwd" ] || fail "herdr reports no cwd"
  case "$agent_status" in
    idle | working | blocked | done | unknown) ;;
    *) fail "unexpected agent_status '$agent_status'" ;;
  esac
  help=$("$herdr" agent prompt --help 2>&1)
  case "$help" in
    *--wait*--timeout*) ;;
    *) fail "herdr agent prompt lacks --wait/--timeout" ;;
  esac
  transcript="$HOME/.claude/projects/$(printf '%s' "$cwd" | tr '/.' '--')/$session.jsonl"
  [ -f "$transcript" ] || fail "transcript not found: $transcript"
  last_turn "$transcript" >/dev/null || fail "no parseable assistant timestamp in transcript"
  jq -c 'select(.type == "assistant") | .message.usage' "$transcript" | tail -1 \
    | jq -e '(.cache_read_input_tokens | numbers) and (.cache_creation_input_tokens | numbers)' >/dev/null \
    || fail "transcript usage lacks cache token counts"
}

arm() {
  pane="$1"
  secs=$(seconds "${2:-${default_hours}h}")
  if armed_pid "$pane" >/dev/null; then
    notify "$pane already armed"
    return 0
  fi
  preflight

  deadline=$(( $(date +%s) + secs ))
  mkdir -p "$state"
  nohup "$0" run "$pane" "$session" "$transcript" "$deadline" >>"$state/log" 2>&1 &
  printf '%s\n%s\n' "$!" "$deadline" >"$(pidfile "$pane")"
  badge "$pane" "$deadline"
  warn=
  [ -n "$("$herdr" pane get "$pane" 2>/dev/null | jq -r '.result.pane.tokens.warm // empty')" ] \
    || warn=", sidebar badge failed"
  notify "$pane armed until $(date -r "$deadline" +%H:%M)$warn"
}

disarm() {
  if pid=$(armed_pid "$1"); then
    # Remove the pidfile first so the runner's EXIT trap treats this as a disarm.
    rm -f "$(pidfile "$1")"
    kill "$pid" 2>/dev/null || true
    badge "$1"
    notify "$1 disarmed"
  fi
}

run() {
  pane="$1" session="$2" transcript="$3" deadline="$4"
  stopped=
  cleanup() {
    rc=$?
    # Pidfile gone or re-armed means disarm owns cleanup.
    [ "$(sed -n 1p "$(pidfile "$pane")" 2>/dev/null)" = "$$" ] || return 0
    [ -n "$stopped" ] || { log "died (exit $rc)"; notify "$pane runner died unexpectedly, see $state/log"; }
    rm -f "$(pidfile "$pane")"
    badge "$pane"
  }
  trap cleanup EXIT
  log() { echo "$(date '+%F %T') $pane $*"; }
  stop() { stopped=1; log "$1"; notify "$pane stopped: $1"; exit 0; }

  while :; do
    now=$(date +%s)
    [ "$now" -lt "$deadline" ] || stop "window ended"
    [ "$(agent_field "$pane" agent_session.value)" = "$session" ] || stop "session left the pane"
    # Claude appends metadata lines while idle, so mtime overstates cache freshness.
    last=$(last_turn "$transcript") || stop "cannot read last turn time from transcript"
    idle=$(( now - last ))
    # Machine sleep can overshoot the TTL; pinging a cold cache just pays the rewrite early.
    [ "$idle" -lt "$ttl" ] || stop "cache already cold (idle $((idle / 60))m)"
    if [ "$idle" -lt "$interval" ]; then
      nap=$(( interval - idle ))
      [ "$nap" -le $(( deadline - now )) ] || nap=$(( deadline - now ))
      sleep "$nap"
      continue
    fi
    case "$(agent_field "$pane" agent_status)" in
      idle | done) ;;
      *) sleep 60; continue ;;
    esac

    "$herdr" agent prompt "$pane" "$ping_text" --wait --timeout 300000 >/dev/null || stop "ping failed"
    # herdr can report idle before Claude flushes the reply to the transcript.
    i=0
    until [ "$(last_turn "$transcript" || echo 0)" -gt "$last" ]; do
      [ "$i" -lt 30 ] || stop "ping reply never reached the transcript"
      sleep 1
      i=$((i + 1))
    done
    usage=$(jq -c 'select(.type == "assistant") | .message.usage' "$transcript" | tail -1)
    read_t=$(printf '%s' "$usage" | jq -r '.cache_read_input_tokens // 0')
    write_t=$(printf '%s' "$usage" | jq -r '.cache_creation_input_tokens // 0')
    log "ping read=$read_t write=$write_t"
    if [ "$read_t" -eq 0 ] || [ $(( write_t * 10 )) -ge "$read_t" ]; then
      stop "ping read $read_t, wrote $write_t"
    fi
  done
}

status() {
  found=
  for f in "$state"/*.pid; do
    [ -f "$f" ] || continue
    pid=$(sed -n 1p "$f")
    if kill -0 "$pid" 2>/dev/null; then
      found=1
      basename "$f" .pid | tr '_' ':'
    else
      rm -f "$f"
    fi
  done
  [ -n "$found" ] || echo "none armed"
  [ -f "$state/log" ] && tail -5 "$state/log"
  return 0
}

wait_key() {
  saved=$(stty -g </dev/tty)
  stty -icanon -echo min 1 </dev/tty
  dd bs=1 count=1 </dev/tty >/dev/null 2>&1
  stty "$saved" </dev/tty
}

# Raw key reads so q/esc cancel without Enter; only digits are accepted.
read_digits() {
  saved=$(stty -g </dev/tty)
  trap 'stty "$saved" </dev/tty' EXIT
  stty -icanon -echo min 1 </dev/tty
  esc=$(printf '\033') del=$(printf '\177') bs=$(printf '\010')
  buf=
  while :; do
    c=$(dd bs=1 count=1 </dev/tty 2>/dev/null)
    case "$c" in
      "") printf '%s' "$buf"; return 0 ;;
      q | Q | "$esc") return 1 ;;
      [0-9]) buf="$buf$c"; printf '%s' "$c" >/dev/tty ;;
      "$del" | "$bs") [ -n "$buf" ] && { buf=${buf%?}; printf '\b \b' >/dev/tty; } ;;
    esac
  done
}

case "${1:-}" in
  prompt)
    pane="${HERDR_ACTIVE_PANE_ID:-}"
    [ -n "$pane" ] || { echo "no active pane" >&2; exit 1; }
    if armed_pid "$pane" >/dev/null; then
      echo "keepwarm $pane: on until $(date -r "$(sed -n 2p "$(pidfile "$pane")")" +%H:%M)"
    elif ! err=$(quiet=1 preflight 2>&1); then
      echo "keepwarm $err"
      printf 'press any key to close'
      wait_key
      exit 0
    else
      echo "keepwarm $pane: off"
    fi
    printf 'hours to keep warm (0 = off, q/esc = cancel) [%s]: ' "$default_hours"
    hours=$(read_digits) || exit 0
    case "${hours:-$default_hours}" in
      0 | 00*) disarm "$pane" ;;
      *) disarm "$pane"; arm "$pane" "${hours:-$default_hours}h" ;;
    esac
    ;;
  arm) [ $# -ge 2 ] || usage; arm "$2" "${3:-${default_hours}h}" ;;
  disarm) [ $# -eq 2 ] || usage; disarm "$2" ;;
  check) [ $# -eq 2 ] || usage; pane="$2"; preflight; echo "$pane: ok" ;;
  run) [ $# -eq 5 ] || usage; run "$2" "$3" "$4" "$5" ;;
  status) status ;;
  *) usage ;;
esac
