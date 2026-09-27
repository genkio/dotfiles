#!/usr/bin/env bash

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

_attach_bin=${HERDR_BIN_PATH:-herdr}

attach_target() { printf '%s\n' "${HERDR_ACTIVE_PANE_ID:-}"; }
attach_cwd() { printf '%s\n' "${HERDR_ACTIVE_PANE_CWD:-$PWD}"; }
attach_notify() { "$_attach_bin" notification show "$1" --body "$2" >/dev/null 2>&1 || true; }
attach_send() { "$_attach_bin" pane send-text "$1" "$2 " >/dev/null; }

# vim-style list: j/k move, / opens the query, esc closes it (or quits when closed)
attach_fzf_nav=(
  --no-input
  --bind 'j:down,k:up,/:show-input+unbind(j,k,/)'
  # hide-input inside transform drops the query change, so it stays outside
  --bind 'esc:transform([ "$FZF_INPUT_STATE" = enabled ] || echo abort)+clear-query+hide-input+rebind(j,k,/)'
)
