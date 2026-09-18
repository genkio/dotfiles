#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

CONFIG="$HOME/.config/aerospace/aerospace.toml"

persistent="$(sed -n 's/^persistent-workspaces *= *\[\(.*\)\].*/\1/p' "$CONFIG" \
                | tr -d ' "')"

[ -n "$persistent" ] || exit 0

home="${persistent%%,*}"

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
