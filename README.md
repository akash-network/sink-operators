# Akash Sink operators

Relayer and reporter services for bridging AKT from Akash to Solana.

- **Relayer:** submits signed Akash headers and transfer proofs to Solana.
- **Reporter:** observes finalized Solana outcomes and reports them to Akash.
- **Header encoder:** Rust helper called by the relayer; included in the package.

Both services use software keys. The Linux package includes Node, dependencies,
the header encoder, configuration examples and systemd units.

## Documentation

| Task                                    | Guide                                           |
| --------------------------------------- | ----------------------------------------------- |
| Download, configure and start a service | [Installation](docs/install.md)                 |
| Monitor, recover or upgrade an operator | [Operations](docs/operations.md)                |
| Build, test or cut a release            | [Development and releases](docs/development.md) |
| Review dependency advisories            | [Security](SECURITY.md)                         |

Supported operator host: **Ubuntu 24.04, x86-64**. Releases are versioned
independently of the Akash node and Solana programs.

**v0.1.0 is a preproduction release for isolated test networks.** Use the
checked-in AKT program interface and explicit `--network testnet`; both mainnet
chain identities are rejected in this mode. The included systemd units select
it. Mainnet use will require a later release with the approved production IDL.
