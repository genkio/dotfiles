#!/usr/bin/env bash
# Stop hook: speak Claude's final reply aloud via macOS `say`. Code blocks and
# tables are announced ("python code block skipped") instead of read out.
# New reply kills any speech still playing, also across parallel sessions:
# latest reply wins.
#
# Skips entirely (no summary, no speech) when system output is muted.
#
# Daily driving (zsh aliases in .zsh_aliases):
#   tts -> mute current reply; tts off / tts on -> persistent toggle
#
# Config (env): CLAUDE_TTS_ENGINE (kokoro | say, default kokoro: local neural
# TTS via kokoro-say.py, falls back to say if broken),
# CLAUDE_TTS_KOKORO_VOICE (default af_heart), CLAUDE_TTS_KOKORO_SPEED (default 1.1),
# CLAUDE_TTS_VOICE / CLAUDE_TTS_RATE (say engine only, default Samantha / 200 wpm),
# CLAUDE_TTS_MAX_CHARS (0 = unlimited), CLAUDE_TTS_DRY=1 prints instead of speaks,
# CLAUDE_TTS_SUMMARIZE (default 1: replies over CLAUDE_TTS_SUMMARIZE_MIN chars,
# default 400, get rewritten for the ear by claude -p haiku, ~5s extra latency).
# Default voice is rough; download a premium one (System Settings >
# Accessibility > Spoken Content > System Voice, e.g. "Ava (Premium)") and set
# CLAUDE_TTS_VOICE=Ava in settings.json env block.
set -u

[ -f "$HOME/.claude/tts-off" ] && exit 0
# set for the nested summarizer claude -p run, whose own Stop hook lands here
[ "${CLAUDE_TTS_SKIP:-0}" = "1" ] && exit 0
# muted output -> skip all: no haiku tokens, no speech. tracks the active
# device (speakers muted skips, but earpods live speaks). non-macos/failure
# yields empty -> not "true" -> proceeds
[ "$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)" = "true" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
# continuation forced by a blocking stop hook (e.g. comments-review audit):
# its reply is hook meta-work, and speaking it would kill the real reply's
# speech launched at the first stop
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
[ -f "$transcript" ] || exit 0

# final reply = trailing assistant entries after the last user-type entry
# (tool results count as user entries, so mid-turn text between tool calls is
# excluded). sidechain entries belong to subagents, never spoken.
extract() {
  jq -rs '
    [ .[]
      | select(.isSidechain != true)
      | select(.type == "assistant" or .type == "user") ] as $turns
    | ($turns | map(.type) | rindex("user") // -1) as $i
    | [ $turns[($i + 1):][]
        | .message.content
        | if type == "array" then .[] else empty end
        | select(.type? == "text")
        | .text ]
    | join("\n\n")
  ' "$transcript" 2>/dev/null
}

# Stop fires before the final text entry is flushed to the transcript (only
# the thinking entry is on disk yet, observed on v2.1.201) -> poll for it
text=""
for _ in $(seq 1 15); do
  text="$(extract)"
  [ -n "$text" ] && break
  sleep 0.2
done
[ -n "$text" ] || exit 0

# text may land as several entries -> don't speak until reads settle
for _ in $(seq 1 5); do
  sleep 0.3
  next="$(extract)"
  [ "$next" = "$text" ] && break
  text="$next"
done

speech="$(printf '%s\n' "$text" | awk '
  /^[[:space:]]*```/ {
    if (incode) { incode = 0 }
    else {
      incode = 1
      lang = $0
      sub(/^[[:space:]]*```+[[:space:]]*/, "", lang)
      print (lang == "" ? "Code block skipped." : lang " code block skipped.")
    }
    next
  }
  incode { next }
  /^[[:space:]]*\|/ { if (!intable) { print "Table skipped."; intable = 1 }; next }
  { intable = 0 }
  /^[[:space:]]*([-*_][[:space:]]*){3,}$/ { next }
  {
    line = $0
    sub(/^#+[[:space:]]*/, "", line)
    sub(/^[[:space:]]*[-*+][[:space:]]+/, "", line)
    sub(/^[[:space:]]*>[[:space:]]*/, "", line)
    print line
  }
' | sed -E \
    -e 's/!\[([^]]*)\]\([^)]*\)/\1/g' \
    -e 's/\[([^]]*)\]\([^)]*\)/\1/g' \
    -e 's|https?://[^[:space:]]+|link|g' \
    -e 's/\*\*//g; s/__//g; s/`//g')"
[ -n "${speech//[[:space:]]/}" ] || exit 0

min="${CLAUDE_TTS_SUMMARIZE_MIN:-400}"
if [ "${CLAUDE_TTS_SUMMARIZE:-1}" = "1" ] && [ "${#speech}" -gt "$min" ] \
  && command -v claude >/dev/null 2>&1; then
  sfile="${TMPDIR:-/tmp}/claude-tts-summary.txt"
  : > "$sfile"
  # set -m: own process group, so the 30s cap below can kill claude and its
  # children, not just the subshell. A hung call would otherwise stall the
  # stop for the hook's full 60s timeout.
  set -m
  ( printf '%s\n' "$speech" | CLAUDE_TTS_SKIP=1 claude -p --model haiku \
    "Rewrite this AI coding assistant reply to be read aloud by text to speech. At most 4 short spoken sentences, plain English, no markdown, symbols, or URLs. Cover what was done or found, key numbers or decisions, and anything I must do next. Lines like 'code block skipped' mean code is shown in the terminal; if the code matters, say so." \
    > "$sfile" 2>/dev/null ) &
  spid=$!
  set +m
  tries=0
  while kill -0 "$spid" 2>/dev/null && [ "$tries" -lt 100 ]; do
    sleep 0.3
    tries=$((tries + 1))
  done
  kill -- -"$spid" 2>/dev/null
  summary="$(cat "$sfile" 2>/dev/null)"
  [ -n "${summary//[[:space:]]/}" ] && speech="$summary"
fi

max="${CLAUDE_TTS_MAX_CHARS:-0}"
if [ "$max" -gt 0 ] && [ "${#speech}" -gt "$max" ]; then
  speech="${speech:0:$max}. Reply truncated."
fi

if [ "${CLAUDE_TTS_DRY:-0}" = "1" ]; then
  printf '%s\n' "$speech"
  exit 0
fi

pidfile="${TMPDIR:-/tmp}/claude-tts.pid"
spool="${TMPDIR:-/tmp}/claude-tts.txt"

# newer reply supersedes whatever is still being spoken
if oldpid="$(cat "$pidfile" 2>/dev/null)" && [ -n "$oldpid" ]; then
  case "$(ps -p "$oldpid" -o comm= 2>/dev/null)" in
    */say | */afplay | */python*) kill "$oldpid" 2>/dev/null ;;
  esac
fi

printf '%s\n' "$speech" > "$spool"
kokoro="$HOME/.claude/hooks/kokoro-say.py"
# verify the venv interpreter (from the script's shebang) exists, not just the
# script: a missing venv exec-fails 127 in the background with no say fallback
kokoro_py="$(sed -n '1s|^#!||p' "$kokoro" 2>/dev/null)"
if [ "${CLAUDE_TTS_ENGINE:-kokoro}" = "kokoro" ] && [ -x "$kokoro" ] && [ -x "$kokoro_py" ]; then
  "$kokoro" "$spool" >/dev/null 2>&1 &
else
  # always pass -v: with System Voice set to a Siri voice, say without -v
  # synthesizes silence and exits 0
  /usr/bin/say -v "${CLAUDE_TTS_VOICE:-Samantha}" -r "${CLAUDE_TTS_RATE:-200}" -f "$spool" \
    >/dev/null 2>&1 &
fi
echo $! > "$pidfile"
disown
exit 0
