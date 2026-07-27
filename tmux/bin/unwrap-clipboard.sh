#!/usr/bin/env bash
set -euo pipefail

# Alacritty's vi mode can't pipe a yank through a filter, so reflow whatever is
# already on the clipboard in place: yank with y, then hit the unwrap binding.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

joined=$(pbpaste | "$here/unwrap-lines.sh")
# empty means non-text clipboard (image, file) - leave it alone
[ -z "$joined" ] && exit 0

printf -- '%s' "$joined" | pbcopy
