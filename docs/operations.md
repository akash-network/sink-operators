# Operator operations

- [Relayer](#relayer)
- [Reporter](#reporter)
- [Upgrade or roll back](#upgrade-or-roll-back)

## Relayer

The relayer pays SOL to upload headers, verify proofs and resolve transfers.
Its payer needs header-update permission when the light client restricts relaying.
Use owned, replaying RPC nodes with the required historical proof data.

```bash
systemctl status akt-relayer
journalctl -u akt-relayer -f
```

Check that authenticated headers advance, transfers reach their permanent Solana
outcome, and the payer retains enough SOL. Alert on stale or frozen clients,
repeated RPC failures, contradictory outcomes and exhausted transfer budgets.

Keep `/var/lib/akt-relayer` across service updates and restarts. It contains
signed transaction intents, proof/header journals and the spend ledger. A restart
reconciles existing transactions before retrying. Do not delete locks while a
process is running or restore an old journal over newer paid work.

After investigating a transfer's spending limit, stop the daemon and explicitly
reset only that transfer's budget:

```bash
systemctl stop akt-relayer
runuser -u akt-relayer -- /opt/akt-bridge/current/bin/akt-relayer run \
  --config /etc/akt-relayer/config.json \
  --reset-budget 'AKASH_OWNER/HEIGHT/SEQUENCE'
systemctl start akt-relayer
```

This permits additional spending; it does not reverse transactions. A frozen or
expired light client requires the bridge governance recovery procedure. Restarting
the service cannot repair it.

## Reporter

Each reporter needs its own Akash signing account and independent observations.
Governance must admit the public address to the current reporter policy. Fund it
with AKT for fees. Do not reuse a validator consensus key.

```bash
systemctl status akt-reporter
journalctl -u akt-reporter -f
```

The default unit runs in preview. Preview makes RPC queries but does not load a
signing key or broadcast. Once admitted, verify a successful scan before enabling
the broadcast override in the [installation guide](install.md#start).

Watch for policy changes, missed observations, contradictory outcomes, low AKT,
unavailable transaction history and stale finalized state. Keep finalized Solana
transactions for the challenge period plus the longest expected outage. An
unavailable transaction is not evidence of a void.

Run one signing process per reporter address. Confirm a real canary's finalized
Solana outcome, native votes, settlement and backing before accepting an operator.
A running unit alone is not sufficient.

## Upgrade or roll back

1. Download and verify the candidate into a new `/opt/akt-bridge/releases/TAG`.
2. Stop the affected unit. Back up its key/config securely and retain all current
   journals. Confirm release notes allow the existing configuration and state.
3. Run the candidate's `check` command. Replace `current` atomically using the
   installation commands and restart the unit.
4. Confirm fresh headers, transfer progress and observations. Upgrade one
   operator at a time.
5. To roll back, stop the service and point `current` to the previous compatible
   release. Keep the newest journals. Software rollback cannot undo transactions.
