#!/bin/sh

# after-startup-command, which fires only when AeroSpace itself launches.
#
# PATH is spelled out because AeroSpace hands its children a Homebrew prefix of
# its own choosing - `/opt/homebrew/bin` on this machine - and a bare
# `sketchybar` on an Intel Mac would resolve to nothing and never start the bar,
# silently. Every other script here spells both prefixes for the same reason.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Anything still running here is stale by definition: AeroSpace is launching,
# so whatever fed these died with the last instance. Reclaim rather than add to
# them. sketchybar in particular takes a lock file and a survivor wins it - a
# bar orphaned to launchd (PPID 1) once beat every launch that followed,
# including the one at login, so the machine came up with a process, no bar and
# nothing able to replace it. borders does not lock at all and simply stacks: 8
# copies, measured.
pkill -x sketchybar
pkill -x borders

sketchybar &

"$(dirname "$0")/reclaim-workspaces.sh"

# The bar may well have outlived the WM - quitting AeroSpace from the bar's own
# x button is the obvious way back here - and a second sketchybar just bows out
# on the lock file, so sketchybarrc's resync never runs. Hence this one, which
# also starts and configures borders on the way through chrome.sh.
"$(dirname "$0")/sync.sh" force
