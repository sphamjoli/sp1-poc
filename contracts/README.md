# Bridge contracts

Solidity contracts own bridge liquidity, claims, validator attestations, staking principal and reward reserves. They are local research contracts; read the root [security assumptions](../SECURITY.md) and [architecture](../ARCHITECTURE.md).

## Build and test

From this directory, install the locked tooling with `bun install --frozen-lockfile`. Initialise the repository's pinned submodules before building.

```bash
forge fmt --check
forge build
forge test --fuzz-runs 1000
```

The fork-based fixtures expect RPCs with chain IDs 1 and 8453. Set `ETH_RPC_URL` and `BASE_RPC_URL` to isolated local Anvil instances. The [shared CI workflow](../.github/workflows/ci.yml) shows the exact fixture startup.

## Components

- `Bridge` receives deposits, commits exit leaves and pays claims from destination liquidity.
- `ValidatorManager` owns membership, certificates, BLS attestations, quorum and settlement replay state.
- `StakeManager` separates principal from funded and accrued rewards, processes exits and protects those liabilities from sweeps.
- Public interfaces document caller-visible guarantees; unit and fuzz tests exercise transitions and accounting.

Use the root `make start-docker-stack STACK_NAME=docker` to deploy development proxies and generate their runtime addresses. The old Fibonacci template deployment commands do not describe these contracts.

The [accounting design](../docs/design/reward-accounting.md) explains storage and commitment changes. Recreate local deployments for these changes. Existing populated contracts require a separately reviewed storage migration and outstanding-claim decision before upgrading.
