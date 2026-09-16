#!/bin/sh

# AeroSpace names a workspace after the mission control space it first found a
# window on, so a restart can strand windows on a workspace this config never
# mentions - a `5` next to a `1` on the bar, with no binding that reaches it.
# Move those windows back into the persistent set, which is read out of
# aerospace.toml rather than repeated here.
#
# Startup only, as the callbacks that would catch a mid-session stray also fire
# during ordinary window moves, and this is not a policy worth enforcing against
# a deliberate one.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

CONFIG="$HOME/.config/aerospace/aerospace.toml"

persistent="$(sed -n 's/^persistent-workspaces *= *\[\(.*\)\].*/\1/p' "$CONFIG" \
                | tr -d ' "')"

# No declared set means every workspace would count as a stray. Do nothing.
[ -n "$persistent" ] || exit 0

home="${persistent%%,*}"

# after-startup-command fires before AeroSpace has finished finding windows, so
# wait for the first one rather than reclaiming an empty list.
i=0
while [ -z "$(aerospace list-windows --all --format '%{window-id}' 2>/dev/null)" ] \
      && [ "$i" -lt 25 ]; do
  sleep 0.2
  i=$((i + 1))
done

for ws in $(aerospace list-workspaces --monitor all --empty no); do
  case ",$persistent," in
    *",$ws,"*) continue ;;
  esac

  for wid in $(aerospace list-windows --workspace "$ws" --format '%{window-id}'); do
    aerospace move-node-to-workspace --window-id "$wid" "$home"
  done
done
