#!/bin/sh

# The bar's x button, and a true quit: the whole stack goes, not just the WM.
# Relaunching AeroSpace brings the other two back on its own, since
# after-startup-command runs startup.sh, which starts the bar and then reaches
# borders through the chrome sync.
#
# AeroSpace has no quit verb of its own, so all three go by SIGTERM. sketchybar
# is listed last because it is this script's parent. The memo files are left
# alone: startup.sh comes back through `force`, which ignores them.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

killall AeroSpace borders sketchybar
