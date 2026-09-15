#!/usr/bin/env bash
#
# Interactive phase picker: what a bare `make` runs.
#
# The phase names are the one thing this repo expects you to know before it will
# do anything, and on a new machine that is exactly when you do not know them.
#
# Builtins and stty only. fzf is the obvious tool for this and is deliberately
# not used: it arrives with the `core` phase, so it cannot be a dependency of
# the menu whose job is to offer to run `core`.
#
# Everything is drawn on /dev/tty rather than stdout, so `make 2>&1 | tee
# setup.log` still works and the redraw frames stay out of the log.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Display order only. opinionated-flow.sh fixes the real run order, because
# touchid has to follow the last sudo of the run whatever is picked here.
PHASES=(macos core apps dev touchid)
# Kept short on purpose: the whole row has to fit 80 columns, which is what a
# stock Terminal.app opens at on the machines this menu is for.
WHAT=(
  "system prefs, remote login, updates off"
  "homebrew + mise, CLI tools, stow, tmux"
  "GUI casks, hammerspoon, sublime, mpv"
  "Brewfile.dev, mise toolchains, agents"
  "pam_tid for sudo"
)
NOTE=(
  "start here"
  "installs homebrew"
  ""
  "slow on Intel"
  "runs last"
)
PICKED=(1 1 1 1 1)

# No controlling terminal (a pipeline with no tty, CI, a hook): say what the
# menu would have offered instead of blocking on a read that can never return.
if ! { exec 3<>/dev/tty; } 2>/dev/null; then
  err "no terminal to prompt on. Name the phases instead:"
  printf '  make %s\n' "${PHASES[@]}" >&2
  err "or 'make all' for every phase, 'make bootstrap' for a usable machine."
  exit 1
fi

TTY_STATE="$(stty -g <&3)"
restore_term() {
  stty "$TTY_STATE" <&3 2>/dev/null || true
  printf '\033[?25h' >&3
}
trap restore_term EXIT

# min 1 time 0: one keypress at a time, no line buffering, nothing echoed.
stty -echo -icanon min 1 time 0 <&3
printf '\033[?25l' >&3

{
  printf '\n  \033[1mPick the phases to run.\033[0m\n'
  printf '  \033[2m↑↓ or jk move · space toggle · a all · n none · enter run · q quit\033[0m\n\n'
} >&3

DREW=0
draw() {
  local i box arrow
  # Every redraw reprints in place, so jump back over the previous frame.
  if [[ "$DREW" -eq 1 ]]; then printf '\033[%dA' "${#PHASES[@]}" >&3; else DREW=1; fi
  for i in "${!PHASES[@]}"; do
    [[ "${PICKED[i]}" -eq 1 ]] && box="x" || box=" "
    [[ "$i" -eq "$CURSOR" ]] && arrow=$'\033[36m❯\033[0m' || arrow=" "
    printf '\033[2K  %b [%s] %-8s \033[2m%-40s %s\033[0m\n' \
      "$arrow" "$box" "${PHASES[i]}" "${WHAT[i]}" "${NOTE[i]}" >&3
  done
}

# Arrow keys arrive as ESC [ A (or ESC O A on an application-mode keypad). A
# bare Esc is that same first byte, so the follow-up read needs a deadline
# rather than blocking forever on it.
#
# The deadline is 1 and not a fraction because macOS ships bash 3.2, where
# `read -t 0.3` is not slow, it is a hard error ("invalid timeout
# specification") - and this script exists for machines with nothing installed
# yet, so /usr/bin/env bash is exactly that 3.2. A whole second is invisible for
# a real arrow key, whose bytes are already buffered; it is only felt on a bare
# Esc, which does nothing anyway. Unrecognised sequences are ignored rather than
# quitting, so half an arrow off a slow link is harmless. q is the only way out.
read_key() {
  local k rest
  IFS= read -rsn1 k <&3 || { echo quit; return; }
  if [[ "$k" == $'\033' ]]; then
    rest=""
    IFS= read -rsn2 -t 1 rest <&3 || true
    case "$rest" in
      '[A' | 'OA') echo up ;;
      '[B' | 'OB') echo down ;;
      *) echo skip ;;
    esac
    return
  fi
  case "$k" in
    "") echo enter ;;
    " ") echo space ;;
    k | K) echo up ;;
    j | J) echo down ;;
    a | A) echo all ;;
    n | N) echo none ;;
    q | Q) echo quit ;;
    *) echo skip ;;
  esac
}

CURSOR=0
draw
while true; do
  # Assignments, not (( ... )): an arithmetic command evaluating to 0 returns
  # exit status 1, which errexit would treat as a failure and kill the picker.
  case "$(read_key)" in
    up) CURSOR=$(((CURSOR - 1 + ${#PHASES[@]}) % ${#PHASES[@]})) ;;
    down) CURSOR=$(((CURSOR + 1) % ${#PHASES[@]})) ;;
    space) PICKED[CURSOR]=$((1 - PICKED[CURSOR])) ;;
    all) for i in "${!PICKED[@]}"; do PICKED[i]=1; done ;;
    none) for i in "${!PICKED[@]}"; do PICKED[i]=0; done ;;
    enter) break ;;
    quit)
      printf '\n  cancelled.\n\n' >&3
      exit 130
      ;;
  esac
  draw
done

ARGS=()
CHOSEN=()
for i in "${!PHASES[@]}"; do
  if [[ "${PICKED[i]}" -eq 1 ]]; then
    ARGS+=(--phase "${PHASES[i]}")
    CHOSEN+=("${PHASES[i]}")
  fi
done

if [[ ${#ARGS[@]} -eq 0 ]]; then
  printf '\n  Nothing selected, nothing to do.\n\n' >&3
  exit 0
fi

printf '\n  \033[36m→\033[0m %s\n\n' "${CHOSEN[*]}" >&3

# exec replaces this process, so the EXIT trap never fires: put the terminal
# back by hand first, and close the tty fd so the flow script does not inherit
# it. Exec rather than call, so its exit status is the one make sees.
restore_term
trap - EXIT
exec 3>&-
exec bash "$SCRIPT_DIR/opinionated-flow.sh" "${ARGS[@]}" "$@"
