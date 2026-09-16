#!/bin/sh

# rcmd-enter. Outer gaps go with the chrome: a hidden bar and the gap that was
# making room for it looks like a stuck window.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

aerospace fullscreen --no-outer-gaps

"$(dirname "$0")/sync.sh"
