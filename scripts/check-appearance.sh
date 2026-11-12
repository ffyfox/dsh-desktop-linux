#!/usr/bin/env bash
# Run source regressions after fetch-upstream.sh, apply-patches.sh and pnpm install.
# Native compositor smoke remains separate and requires an unpacked desktop build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="${DSH_APPEARANCE_SOURCE:-$ROOT/upstream}"
[[ -f "$UPSTREAM/apps/desktop/src/client-appearance.ts" ]] || {
  echo "Apply the complete patch series to upstream/ before running appearance checks." >&2
  exit 1
}
# Local RPC in the Host tests must not pass through a user's HTTP proxy.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export DSH_TELEMETRY_DISABLED=1
# Use the same Node-compatible pnpm selector as the packaging scripts.
source "$ROOT/scripts/select-pnpm.sh"
"$PNPM" --dir "$UPSTREAM" exec vitest run apps/desktop/tests apps/desktop-host/tests --maxWorkers=4
python3 -m unittest discover -s "$UPSTREAM/apps/desktop/tests/wayland" -p 'test_*.py' -v
