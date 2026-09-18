#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PHASES=(macos core apps dev touchid)
WHAT=(
  "system prefs, remote login, updates off"
  "homebrew + mise, CLI tools, stow"
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

stty -echo -icanon min 1 time 0 <&3
printf '\033[?25l' >&3

{
  printf '\n  \033[1mPick the phases to run.\033[0m\n'
  printf '  \033[2m↑↓ or jk move · space toggle · a all · n none · enter run · q quit\033[0m\n\n'
} >&3

DREW=0
draw() {
  local i box arrow
  if [[ "$DREW" -eq 1 ]]; then printf '\033[%dA' "${#PHASES[@]}" >&3; else DREW=1; fi
  for i in "${!PHASES[@]}"; do
    [[ "${PICKED[i]}" -eq 1 ]] && box="x" || box=" "
    [[ "$i" -eq "$CURSOR" ]] && arrow=$'\033[36m❯\033[0m' || arrow=" "
    printf '\033[2K  %b [%s] %-8s \033[2m%-40s %s\033[0m\n' \
      "$arrow" "$box" "${PHASES[i]}" "${WHAT[i]}" "${NOTE[i]}" >&3
  done
}

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

restore_term
trap - EXIT
exec 3>&-
exec bash "$SCRIPT_DIR/opinionated-flow.sh" "${ARGS[@]}" "$@"
