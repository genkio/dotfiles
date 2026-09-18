#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

joined=$(pbpaste | "$here/unwrap-lines.sh")
[ -z "$joined" ] && exit 0

printf -- '%s' "$joined" | pbcopy
