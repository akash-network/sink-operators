#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[[ "$(uname -sm)" == 'Linux x86_64' ]] || { echo 'Build on Linux x86-64.' >&2; exit 1; }
[[ $# == 1 && "$1" == /* && ! -e "$1" ]] || { echo 'usage: build.sh /new/absolute/output' >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Release source must be committed and clean.' >&2; exit 1; }
commit=$(git rev-parse HEAD)
version=$(node -p 'require("./package.json").version')
mkdir -p .cache
stage=$(mktemp -d "$root/.cache/package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
export CARGO_TARGET_DIR=$root/.cache/cargo
cargo build --locked --release --manifest-path tools/header-encoder/Cargo.toml
mkdir -p "$stage/package/bin" "$stage/package/.cache"
git archive "$commit" src interfaces config deploy docs .npmrc package.json package-lock.json LICENSE NOTICE README.md SECURITY.md | tar -x -C "$stage/package"
find "$stage/package/src" -name '*.test.ts' -delete
rm -rf "$stage/package/src/tests" "$stage/package/src/reporter/testdata"
rm -f "$stage/package/src/relayer/test-workspace.ts" "$stage/package/src/relayer/relay-test-fixture.ts"
cp .cache/chain-sdk.tar "$stage/package/.cache/"
(
  cd "$stage/package"
  npm ci --omit=dev --ignore-scripts
)
rm -rf "$stage/package/.cache"
bash scripts/node-runtime.sh "$stage/package/runtime"
install -m 755 .cache/cargo/release/akt-header-encoder "$stage/package/bin/"
install -m 755 scripts/operator.sh "$stage/package/bin/akt-relayer"
install -m 755 scripts/operator.sh "$stage/package/bin/akt-reporter"
{
  printf 'version %s\ncommit %s\nplatform linux_amd64\n' "$version" "$commit"
  node --version
  cargo --version
  sha256sum .cache/chain-sdk.tar
  cd "$stage/package"
  sha256sum bin/akt-header-encoder runtime/bin/node interfaces/*.json
} > "$stage/package/service-build-info.txt"
chmod -R a+rX,go-w "$stage/package"
bash scripts/test-release.sh "$stage/package"
mkdir -p "$(dirname "$1")"
mv "$stage/package" "$1"
