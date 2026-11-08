#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
revision=3b977f0785eef4a5cfdd06747a8084f2cd5161ba
mkdir -p "$root/.cache"
stage=$(mktemp -d "$root/.cache/sdk.XXXXXX")
trap 'rm -rf "$stage"' EXIT
curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 \
  "https://codeload.github.com/akash-network/chain-sdk/tar.gz/$revision" -o "$stage/source.tar.gz"
tar -xzf "$stage/source.tar.gz" -C "$stage" --strip-components=1
(
  cd "$stage/ts"
  npm ci
  npm run build
)
# Exclude TypeScript's machine-specific incremental-build cache from the package.
python3 - "$stage/ts" "$root/.cache/chain-sdk.tar" <<'PY'
import io
from pathlib import Path
import sys
import tarfile

source, destination = map(Path, sys.argv[1:])
paths = [source / "package.json"]
paths += [path for path in source.glob("LICENSE*") if path.is_file()]
paths += [path for path in source.glob("README*") if path.is_file()]
paths += [path for path in (source / "dist").rglob("*") if path.is_file() and path.suffix != ".tsbuildinfo"]
with tarfile.open(destination, mode="w", format=tarfile.PAX_FORMAT) as archive:
    for path in sorted(paths):
        data = path.read_bytes()
        entry = tarfile.TarInfo("package/" + str(path.relative_to(source)))
        entry.size = len(data)
        entry.mode = 0o644
        archive.addfile(entry, io.BytesIO(data))
PY
