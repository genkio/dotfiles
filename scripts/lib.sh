#!/usr/bin/env bash
# Shared logging helpers for the setup scripts. Source, do not execute.
#
# Unified prefixes make provisioning problems greppable across a whole `make`
# run, e.g. `make 2>&1 | grep SETUP_WARN` (or `grep SETUP_` for warnings and
# errors together). warn() = non-fatal, setup keeps going; err() = fatal,
# print right before exiting.

warn() { echo "SETUP_WARN: $*" >&2; }
err() { echo "SETUP_ERROR: $*" >&2; }
