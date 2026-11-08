# Security

Report vulnerabilities privately through GitHub's **Report a vulnerability**
feature. Do not include private keys, mnemonics or authenticated RPC URLs in an
issue. Operators should use dedicated, owner-only software keys and owned RPC
nodes. A reporter's finalized commitment does not make an untrusted RPC truthful.

## Dependency review for v0.1.0

Zod is updated to 4.6.7, which includes the fix for
[GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5).
The lockfile still contains advisories inherited from Anchor/Solana dependencies:

| Dependency                                                                                                       | Disposition for this package                                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bigint-buffer` / GHSA-3gc7-fjrx-p6mg                                                                            | Release installation disables dependency scripts and checks that no native bigint binding is shipped. The supported JavaScript fallback avoids the vulnerable native conversion. |
| `toml` / GHSA-82x6-q7mm-w9cf, GHSA-v5mp-jgw5-2x6j, GHSA-4qx8-w7c3-pj3p, GHSA-9j65-hcg3-gc64, GHSA-9qmh-m7c6-f92p | Anchor's workspace loader uses it to read `Anchor.toml`. The operator constructs programs from bundled IDLs and does not invoke that loader or accept TOML.                      |
| `stream-json` / GHSA-528h-pc64-c93x, GHSA-hqr4-qq8f-hg3x, GHSA-mjw6-4jj6-33hc                                    | These services use web3's HTTP/browser Jayson client. They do not expose Jayson's streaming server or use the affected streaming filters/assembler.                              |
| `uuid` / GHSA-w5hq-g745-h8pq                                                                                     | The HTTP client generates IDs with `v4()`; the affected caller-supplied buffers in v3/v5/v6 are not used.                                                                        |

These are scoped reachability dispositions, not claims that the dependencies are
fixed. CI records current advisories and rejects advisory IDs absent from this
review. Reassess whenever dependency versions or these call paths change.
