# Development and releases

Use Linux x86-64 with Node 24.22.1, Rust 1.89.0, Python 3, protobuf-compiler,
pkg-config and libssl-dev. Rust is pinned by `rust-toolchain.toml`.

## Test

```bash
npm run prepare:sdk
npm ci
npm run typecheck
npm run format:check
npm test
npm run test:encoder
```

`prepare:sdk` builds the pinned public chain-sdk source. The resulting archive's
integrity is checked by `npm ci`. It is a build input under `.cache`, not a
published replacement for chain-sdk. Regeneration excludes only TypeScript's
machine-specific incremental-build cache. Do not replace it with the npm package
of the same version: that package predates the required Sink API.

Tests cover signing, custody, proof bytes, policy, discovery, finalized outcomes,
transaction recovery, spending and process locking. The lock test requires a
native Linux filesystem; a macOS Docker bind mount is not equivalent. These tests
do not claim a live mainnet mint or refund.

## Interfaces

`interfaces/` contains generated Anchor IDLs and types. Regenerate them in the
pinned node/IBC contract repositories and copy the matching outputs together.
The IDL supplies the supported instruction, account and event layouts. Relayer
and reporter clients bind that interface to the configured `programId`; changing
a deployment address does not require regenerating the IDL. The reporter also
checks that `mint` is the canonical mint for that program.

Set RPC endpoints, `akashChainId`, `solanaGenesisHash`, `programId` and the
reporter mint in each deployment's config. Live chain identity, account ownership,
mint authority, freshness and finality checks remain enabled. Use a separate
relayer state directory for each deployment. `--network` remains an explicit
mainnet/testnet safety selection. A contract interface change still needs a
compatible service release; configuration does not change account layouts.

Starting with v0.1.1, reporter addresses are configurable. The v0.1.0 reporter
requires its bundled program address. Reporter signing uses a 32-byte hex
private-key file, never a seed phrase.

A new release is needed for service fixes, dependency updates or changes to the
supported instructions, account/event layouts, proof format or signing format.
Changing endpoints, compatible deployment addresses, keys or supported limits
only requires configuration and a service restart. A contract upgrade that
preserves those interfaces does not by itself require an operator release.

## Build

From a clean, committed checkout:

```bash
bash scripts/build.sh "$PWD/.cache/package"
```

This builds the Rust encoder with its lockfile, installs production dependencies,
downloads the checksum-pinned Node runtime and tests the installed commands.
It writes the source commit and executable/interface hashes into
`service-build-info.txt`. No Akash or Solana node is started.

## Release

1. Review the deployment interface and dependency advisories. Update
   `package.json`, `package-lock.json`, the encoder version and
   `docs/releases/vVERSION.md` together.
2. Merge a signed commit after CI passes, then push a signed `vVERSION` tag.
3. The Release workflow reruns CI on Ubuntu 24.04, packages that verified CI
   artifact with GoReleaser, verifies the extracted archive and uploads a **draft** GitHub
   release. The archive includes the Node runtime and Rust encoder; GoReleaser
   packages them and does not build a Go service.
4. Download the draft assets on a fresh Ubuntu host, verify checksums, key
   custody, configuration, systemd units and the agreed network canary. Publish
   the draft only after recording the actual verification and support scope.
   Preproduction releases do not establish production qualification.

```bash
git tag -s vVERSION -m 'vVERSION'
git push origin vVERSION
gh release edit vVERSION --draft=false --prerelease
```

Releases never rebuild or publish the Akash node or Solana programs. Keep service
keys and runtime journals outside the repository and release directories.
