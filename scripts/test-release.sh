#!/usr/bin/env bash
# Exercise the installed commands without contacting a chain or printing keys.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.cache"
export SOLANA_CACHE=$root/.cache
root=${1:?release directory required}
if find "$root/node_modules/bigint-buffer" -name "*.node" -print -quit | grep -q .; then
  echo "Native bigint-buffer binding must not be shipped." >&2; exit 1
fi
fixture=$(mktemp -d "$SOLANA_CACHE/operator-smoke.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
for role in relayer reporter; do
  command=$root/bin/akt-$role
  "$command" --help > /dev/null
  "$command" --version > /dev/null
  address=$("$command" keys create --out "$fixture/$role.key")
  [[ -n "$address" && "$address" == "$("$command" keys address --key-file "$fixture/$role.key")" ]]
  if "$command" keys create --out "$fixture/$role.key" > /dev/null 2>&1; then
    echo 'key overwrite unexpectedly succeeded' >&2; exit 1
  fi
  chmod 644 "$fixture/$role.key"
  if "$command" keys address --key-file "$fixture/$role.key" > /dev/null 2>&1; then
    echo 'insecure key permissions unexpectedly accepted' >&2; exit 1
  fi
  if [[ "$role" == relayer ]]; then program=$address; fi
  "$root/runtime/bin/node" - "$root" "$fixture" "$role" "$address" "$program" <<'JS'
const { readFileSync, writeFileSync } = require('node:fs');
const [root, fixture, role, address, program] = process.argv.slice(2);
const config = JSON.parse(readFileSync(`${root}/config/${role}.json`, 'utf8'));
config.programId = program;
if (role === 'reporter') {
  config.reporter = address;
  config.mint = program;
  config.keyFile = `${fixture}/reporter.key`;
}
writeFileSync(`${fixture}/${role}.json`, JSON.stringify(config));
writeFileSync(`${fixture}/${role}-wrong-chain.json`, JSON.stringify({ ...config, akashChainId: 'wrong-chain' }));
JS
  # Config checks must not load keys, including the deliberately insecure file.
  "$command" check --config "$fixture/$role.json" > /dev/null
  if [[ "$role" == reporter ]]; then
    "$command" check --config "$fixture/$role.json" --broadcast > /dev/null
  fi
  if "$command" check --config "$fixture/$role-wrong-chain.json" > /dev/null 2>&1; then
    echo 'wrong-chain configuration unexpectedly accepted' >&2; exit 1
  fi
done
echo 'Installed commands, config validation and key custody checks passed.'
