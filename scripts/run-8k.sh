#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$root_dir/build/virtual-second-monitor" ]; then
  "$root_dir/scripts/build-native.sh" >/dev/null
fi

exec "$root_dir/build/virtual-second-monitor" \
  --width 7680 \
  --height 4320 \
  --ppi 280 \
  --refresh 60 \
  --hidpi \
  --name "Debug 8K Display"
