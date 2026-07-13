#!/usr/bin/env bash
# Shared logging helpers for the setup scripts. Source, do not execute.
#
# Unified prefixes make provisioning problems greppable across a whole `make`
# run, e.g. `make 2>&1 | grep SETUP_WARN` (or `grep SETUP_` for warnings and
# errors together). warn() = non-fatal, setup keeps going; err() = fatal,
# print right before exiting.
#
# Both colorize when stderr is a terminal so they stand out in a long run;
# color is dropped when redirected/piped so log files stay clean and still
# grep by prefix.

if [[ -t 2 ]]; then
  _SETUP_YELLOW=$'\033[33m'
  _SETUP_RED=$'\033[31m'
  _SETUP_RESET=$'\033[0m'
else
  _SETUP_YELLOW=""
  _SETUP_RED=""
  _SETUP_RESET=""
fi

warn() { echo "${_SETUP_YELLOW}SETUP_WARN: $*${_SETUP_RESET}" >&2; }
err() { echo "${_SETUP_RED}SETUP_ERROR: $*${_SETUP_RESET}" >&2; }
