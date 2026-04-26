#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root_dir/build/Virtual Second Monitor.app"

if [ "${VSM_FORCE_BUILD:-0}" = "1" ] || [ ! -d "$bundle" ]; then
  "$root_dir/scripts/build-app.sh" >/dev/null
fi

open "$bundle"
