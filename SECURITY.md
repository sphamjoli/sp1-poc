# Security assumptions and reporting

This repository is an unaudited local research prototype. Passing tests demonstrates the tested behaviours, not production bridge security.

## Assets and trust boundaries

Assets at risk include bridge liquidity, validator principal, reward reserves and owner signing authority. Untrusted inputs include receipt and trie bytes, indexed events, RPC responses, wallet data and API requests. The stake and bridge contracts must preserve accounting even when tokens or recipients misbehave.

Known development boundaries:

- Public Anvil keys in `config/runtime.local.json` and the development validator catalogue are fixtures. Anyone can sign as these accounts.
- The default proof loop uses mock SP1 proving.
- The RPC service does not establish finality for a requested numbered block.
- Guest receipt roots lack an authenticated consensus anchor. A proof of consistency with supplied roots does not prove real-chain inclusion.
- The node manager performs owner operations without a production authentication system. Its API and local fork RPCs must remain confined to the development machine.
- Quorum uses live validator membership rather than a historical committee snapshot. Certificate and BLS domain separation does not bind every contract-instance dimension. Cross-contract replay assumptions require protocol review.
- Token allow-lists, cross-chain token mapping and production asset rescue policy are not implemented.
- Owners can upgrade proxies and configure protocol dependencies. Production governance, key custody and recovery are not implemented.
- Reward and stake accounting changes need a storage-layout review and migration plan before any upgrade of existing funded deployments.

Use only development assets and wallets. Do not expose the stack to an untrusted network or use its fixture credentials for other systems.

## Report a vulnerability

Report privately through the repository's [security advisory page](https://github.com/sphamjoli/sp1-poc/security/advisories/new). If private reporting is unavailable, contact the repository owner through their [GitHub profile](https://github.com/sphamjoli) to arrange a private channel. Include affected code, a minimal reproduction and the impact. Avoid posting exploit details against funded deployments in a public issue.

There is no supported production release or independent audit represented by this repository.
