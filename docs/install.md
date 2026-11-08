# Run a relayer or reporter

Download the operator package for the deployed bridge. It includes Node, the
header encoder, dependencies, configuration examples and systemd units. Operators
need no source checkout, compiler, npm, KMS or hardware wallet.

- [Install](#install)
- [Create a key and configure](#create-a-key-and-configure)
- [Use an existing Akash wallet](#use-an-existing-akash-wallet)
- [Use an existing Solana keypair](#use-an-existing-solana-keypair)
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

These releases support isolated test networks. Obtain their Akash chain ID,
Solana genesis hash, deployed AKT program/mint addresses and RPC endpoints from
the deployment handoff. Starting with v0.1.1, compatible deployment addresses are
configured without rebuilding the package. The contracts must implement the
package's supported interfaces, and the mint must belong to the configured AKT
program. `--network testnet` rejects both mainnet identities; production
qualification remains separate.

The relayer needs SOL and header-update permission. The reporter needs AKT for
fees and membership in the current Akash reporter policy. Use dedicated service
keys, separate from validator consensus keys.

## Install

Run these commands as the host administrator:

```bash
TAG=v0.1.1
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

Use either the new-key steps or the existing-wallet steps for your role.

### Create a new key

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
file contains a 32-byte hex secp256k1 private key, not a seed phrase. Neither
belongs in a release or Git.

The software reads the file and signs locally; only signed transactions are sent
to RPC nodes. The JSON configuration contains the key's path, not its contents.

Continue at [Configure](#configure) after creating a new key.

### Use an existing Akash wallet

Use the native Akash node CLI, `akash`, on your secure workstation for this
one-time export. It does not need a running node. The commands below use
`akash keys`; CLI versions that export only encrypted armor cannot produce a
reporter key file directly.

#### Recover the same account

If the wallet is already in an Akash CLI keyring, skip recovery. Set `KEY_HOME`,
`KEY_BACKEND` and `KEY_NAME` below to that keyring and key.

Otherwise, recover from your existing mnemonic into a separate keyring:

```bash
KEY_HOME="$HOME/.akash-reporter-export"
KEY_BACKEND=file
KEY_NAME=existing-reporter
HD_PATH="m/44'/118'/0'/0/0"

akash keys add "$KEY_NAME" --recover --no-backup \
	--hd-path "$HD_PATH" --home "$KEY_HOME" --keyring-backend "$KEY_BACKEND"
```

Enter the mnemonic at the prompt. Use your wallet's actual derivation path and
account index; the example selects the first standard Cosmos account. If the
wallet uses a BIP39 passphrase, add `--interactive` and enter that passphrase.
The keyring encryption password is separate from the BIP39 passphrase.

Print the recovered address:

```bash
akash keys show "$KEY_NAME" --address \
	--home "$KEY_HOME" --keyring-backend "$KEY_BACKEND"
```

Compare it with the address in your existing wallet. Continue only when they
match. Recovery does not create a new on-chain account or move funds.

#### Export and install the private key

Export directly to a new owner-only file. This prints no private key to the
terminal and refuses to overwrite an existing file:

```bash
(
	umask 077
	set -o noclobber
	akash keys export "$KEY_NAME" --unsafe --unarmored-hex --yes \
		--home "$KEY_HOME" --keyring-backend "$KEY_BACKEND" \
		> "$KEY_HOME/reporter.key"
)
```

The result is 64 lowercase hex characters without `0x`. The reporter accepts
this raw private key, not the mnemonic or an encrypted keyring export.

Transfer `reporter.key` to `/root/reporter.key` on the reporter host over SSH.
As the host administrator, install it into the empty service key path:

```bash
test ! -e /etc/akt-reporter/reporter.key &&
	install -o akt-reporter -g akt-reporter -m 0600 \
		/root/reporter.key /etc/akt-reporter/reporter.key

runuser -u akt-reporter -- /opt/akt-bridge/current/bin/akt-reporter \
	keys address --key-file /etc/akt-reporter/reporter.key
```

Confirm the printed address still matches your wallet. Set `reporter` to that
address and `keyFile` to `/etc/akt-reporter/reporter.key` in the config.

Keep a secure backup and remove temporary transfer copies. Continue at
[Configure](#configure).

### Use an existing Solana keypair

Use the existing Solana CLI keypair JSON file, a 64-byte integer array. A
mnemonic or a browser wallet's base58 private-key export is not this format.
Check its address on your workstation:

```bash
solana-keygen pubkey /secure/path/payer-keypair.json
```

Transfer the file to `/root/payer-keypair.json` on the relayer host over SSH.
As the host administrator, install it into the empty service key path:

```bash
test ! -e /etc/akt-relayer/payer-keypair.json &&
	install -o akt-relayer -g akt-relayer -m 0600 \
		/root/payer-keypair.json /etc/akt-relayer/payer-keypair.json

runuser -u akt-relayer -- /opt/akt-bridge/current/bin/akt-relayer \
	keys address --key-file /etc/akt-relayer/payer-keypair.json
```

Confirm the printed address matches your existing Solana wallet. Set
`payerKeyFile` to `/etc/akt-relayer/payer-keypair.json` in the config.

Keep a secure backup and remove temporary transfer copies.

### Configure

Edit `/etc/akt-ROLE/config.json`:

| Both roles                                                                                                            | Role-specific settings                                                                                                        |
| --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Set `akashRpc`, `solanaRpc` and the deployed `programId`. Set the actual test `akashChainId` and `solanaGenesisHash`. | Reporter: set `reporter` to the verified address, `mint` to the verified mint, and keep `keyFile` pointing to `reporter.key`. |
| Preserve the reviewed freshness and fee limits.                                                                       | Relayer: keep `payerKeyFile`, `headerEncoder` and persistent `stateDir` paths from the example.                               |

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

The light-client and access-manager program addresses are discovered from bridge
state. Both configs accept an optional `lightClientProgram` pin if operators must
reject a change to the light-client program.

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
