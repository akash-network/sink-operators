#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
role=$(basename "$0")
exec "$root/runtime/bin/node" --import "$root/node_modules/tsx/dist/loader.mjs" \
  "$root/src/cli/operator.ts" "${role#akt-}" "$@"
