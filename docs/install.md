# Run a relayer or reporter

Download the operator package for the deployed bridge. It includes Node, the
header encoder, dependencies, configuration examples and systemd units. Operators
need no source checkout, compiler, npm, KMS or hardware wallet.

- [Install](#install)
- [Create a key and configure](#create-a-key-and-configure)
- [Start](#start)
- [Upgrade or roll back](#upgrade-or-roll-back)
- [Release process](development.md#release)

## Before you start

Use an x86-64 Linux host with systemd, glibc 2.39 or newer (Ubuntu 24.04), Bash,
CA certificates, curl, tar, Python 3 and libstdc++6. The relayer uses Python's
standard library for its process lock. On Ubuntu, install the host prerequisites:

```bash
apt-get update
apt-get install -y ca-certificates curl tar python3 libstdc++6
```

Run each reporter under a separate operator with
independent Akash and replaying Solana nodes. The Solana node must retain finalized
transactions for the challenge period plus the longest expected outage.

v0.1.0 supports isolated test networks. Obtain their Akash chain ID, Solana genesis
hash, deployed AKT program/mint addresses and RPC endpoints from the deployment
handoff. `--network testnet` rejects both Akash and Solana mainnet identities. The package's compiled IDL must match that program. A release built with development IDs cannot run against mainnet.

The relayer needs SOL and header-update permission. The reporter needs AKT for
fees and membership in the current Akash reporter policy. Use dedicated service
keys, separate from validator consensus keys.

## Install

Run these commands as the host administrator:

```bash
TAG=v0.1.0
VERSION=${TAG#v}
ASSET=akt-bridge_${VERSION}_linux_amd64.tar.gz
BASE=https://github.com/akash-network/sink-operators/releases/download/$TAG
DOWNLOAD=$(mktemp -d /var/tmp/akt-bridge.XXXXXX)
cd "$DOWNLOAD"
curl -fLO "$BASE/$ASSET"
curl -fLO "$BASE/akt-bridge_${VERSION}_checksums.txt"
sha256sum --check "akt-bridge_${VERSION}_checksums.txt"

RELEASE=/opt/akt-bridge/releases/$TAG
test ! -e "$RELEASE"
install -d -m 0755 "$RELEASE"
tar -xzf "$ASSET" -C "$RELEASE"
chown -R root:root "$RELEASE"
chmod -R a+rX,go-w "$RELEASE"
"$RELEASE/bin/akt-reporter" --version
ln -s "releases/$TAG" /opt/akt-bridge/current.next
mv -Tf /opt/akt-bridge/current.next /opt/akt-bridge/current
cd "$RELEASE"
rm -rf "$DOWNLOAD"
```

Check the printed source commit against the release notes. Keep release files
root-owned and immutable to service users. For an upgrade, stop the service
before changing `current`, as described below.

## Create a key and configure

Choose **one role** per service host. Set `ROLE=relayer` or `ROLE=reporter`:

```bash
ROLE=reporter
ACCOUNT=akt-$ROLE
ROOT=/opt/akt-bridge/current
useradd --system --home-dir /var/lib/$ACCOUNT --shell /usr/sbin/nologin "$ACCOUNT"
install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 0700 /etc/$ACCOUNT /var/lib/$ACCOUNT
install -o "$ACCOUNT" -g "$ACCOUNT" -m 0600 \
  "$ROOT/config/$ROLE.json" /etc/$ACCOUNT/config.json
```

Create the key as the service user. Only its **public address** is printed:

```bash
# Reporter host
runuser -u akt-reporter -- "$ROOT/bin/akt-reporter" keys create \
  --out /etc/akt-reporter/reporter.key

# Relayer host
runuser -u akt-relayer -- "$ROOT/bin/akt-relayer" keys create \
  --out /etc/akt-relayer/payer-keypair.json
```

Use only the command for your role. Creation refuses existing files. Back up the
key securely; it is an unencrypted software key protected by its owner and mode
`0600`. The relayer file uses the standard Solana CLI JSON format. The reporter
file contains a secp256k1 private key. Neither belongs in a release or Git.

Edit `/etc/akt-ROLE/config.json`:

| Both roles                                                                                                            | Role-specific settings                                                                                                         |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Set `akashRpc`, `solanaRpc` and the deployed `programId`. Set the actual test `akashChainId` and `solanaGenesisHash`. | Reporter: set `reporter` to the generated address, `mint` to the verified mint, and keep `keyFile` pointing to `reporter.key`. |
| Preserve the reviewed freshness and fee limits.                                                                       | Relayer: keep `payerKeyFile`, `headerEncoder` and persistent `stateDir` paths from the example.                                |

Fund the public address with AKT (reporter) or SOL (relayer). Send the reporter's
public address to the governance coordinator for admission. For a closed relayer
set, the bridge administrator grants the relayer address header-update permission.

Check the local configuration without RPC requests, key loading or transactions:

```bash
runuser -u "$ACCOUNT" -- "$ROOT/bin/akt-$ROLE" check --network testnet --config /etc/$ACCOUNT/config.json
```

`keys address --key-file /absolute/path` checks file custody and prints its
public address. Live network, policy, balance and freshness checks happen when
the service runs.

## Start

Install the role's unit:

```bash
install -m 0644 "$ROOT/deploy/systemd/$ACCOUNT.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now "$ACCOUNT"
journalctl -u "$ACCOUNT" -f
```

The relayer submits proofs immediately. The reporter starts in **preview** and
does not load its key. Before governance admits the address, preview reports
`not a current reporter`; that is not a completed observation test.

After admission, inspect a successful preview scan. Then enable reporter signing:

```bash
install -d -m 0755 /etc/systemd/system/akt-reporter.service.d
cat > /etc/systemd/system/akt-reporter.service.d/broadcast.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/opt/akt-bridge/current/bin/akt-reporter run --network testnet --config /etc/akt-reporter/config.json --watch --broadcast
EOF
systemctl daemon-reload
systemctl restart akt-reporter
journalctl -u akt-reporter -f
```

Run one signer process per reporter account. Confirm a real canary transfer,
its finalized Solana outcome, native reporter votes and backing before accepting
the operator. A running systemd unit alone does not prove successful reporting.
Route repeated RPC, stale-client, contradictory-outcome and failed-transaction
alerts to paging. See [operations](operations.md) for logs, retention and recovery.

## Upgrade or roll back

1. Download and verify the new package into a **new** release directory.
2. Stop the role's unit. Back up `/etc/akt-ROLE` securely and preserve
   `/var/lib/akt-relayer`, including journals and spend records.
3. Check the candidate's compatibility and run its `check` command against the
   existing config. Atomically replace `current`, then restart the unit.
4. Verify fresh headers, transfer progress and reporter observations. Change one
   operator at a time.
5. To roll back, stop the service and point `current` at the previous compatible
   release. Keep current journals: restoring old state can repeat paid work.

Do not delete locks while a relayer is running. A software rollback cannot undo
transactions. Frozen or expired clients use the separate
[operations guide](operations.md).
