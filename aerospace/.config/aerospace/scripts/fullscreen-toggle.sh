#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

aerospace fullscreen --no-outer-gaps

"$(dirname "$0")/sync.sh"
