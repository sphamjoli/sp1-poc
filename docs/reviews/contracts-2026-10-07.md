# Contract adversarial review

Review date: 2026-10-07. Scope: project-owned Solidity bridge, staking, validator contracts and their public-path tests. This is an engineering review of an experimental bridge, not an independent audit or deployment approval.

## Observed defects and changes

The owner could repeatedly withdraw reward funding through `sweepExcess` because it checked only that the requested amount was smaller than reserves. The contract now permits only token assets above principal plus funded reward reserves. Allocated rewards are a subset of those reserves, tracked once in `accruedRewards`.

Reward distribution previously created liabilities without funding, including early bonuses. Each distribution now requires sufficient unallocated funding and reverts atomically when funding is insufficient. Claiming, slashing and full exits update principal, reserve funding and allocated reward liabilities consistently before token payouts.

Inactive exits mixed principal and rewards into one principal deduction. Full exits could delete unpaid rewards, and partial exits left validators in `Unstaking`. Exit settlement now pays full-exit rewards separately, retains rewards on partial exits, and restores active membership after a completed partial exit. Fully slashed validators can burn their otherwise stranded receipt. Jailed top-ups require the resulting stake to meet the minimum, preserve the original staking age, and retain the existing token configuration while the receipt exists.

ERC20 bridge deposits and stakes now require an exact token balance increase. Bridge deposits reject a zero recipient and unintended native value alongside ERC20 transfers. Claims use a reentrancy guard, bind the proof key to the claimed deposit index, and cap the sparse-Merkle path at 32 siblings.

Claim-leaf hashing previously copied the source-chain word into each subsequent field. Standard ABI encoding now commits all nine fields. Confirmed unused internal storage helpers and a debug event were removed.

## Accounting model and alternatives

For each token, `assets >= principal + rewardReserves`, and `rewardReserves >= accruedRewards`. Reward reserves include both unallocated funding and allocated, unclaimed rewards. Reward allocation increases only accrued liabilities; reward payment reduces both accrued liabilities and reserve funding; slashed principal becomes reserve funding; slashed rewards cease being accrued liabilities without duplicating reserve assets.

Keeping one total funding counter plus an allocated subset was chosen over converting reserves to an unallocated-only counter. It preserves the existing reserve meaning and limits changes to existing payout paths. Inferring liabilities from events or token balance was rejected because neither identifies outstanding validator entitlements.

The new mapping consumes one reserved storage-gap slot without moving existing fields. Storage compatibility does not initialise existing accrued liabilities. These changes require fresh deployment or a separately reviewed migration before upgrading any populated staking contract. Corrected claim hashing changes newly constructed claim roots and must be coordinated with consumers. The underlying bridge sparse tree already stores internal function pointers; its existing upgrade validation exemption remains a separate deployment risk.

## Assumptions and evidence

| Assumption | Evidence and result |
| --- | --- |
| Reward funding must remain separate from principal | Existing `principal`, `rewardReserves`, `transferToken` and `sweepExcess` interface define separate ownership; adversarial reserve-drain test rejects the original implementation. |
| Rewards are paid at full exit | Existing exit event exposes reward amount; generated active/inactive exit tests assert actual token movement and zero remaining liabilities. |
| A completed partial exit retains validator membership | Partial exits leave at least the configured minimum stake; public status and NFT ownership are checked after settlement. |
| Token quantities represent received backing | Fee-token tests assert rollback of token receipt, deposit count and stake state. |
| ABI hashing must include every claim field | Generated claim vectors compare with standard ABI encoding, and a weakened commitment mutation fails. |
| Tests must use funded allocations | Legacy tests that expected unclaimable unfunded rewards were replaced; shared fixtures fund reserves through the real token-top-up path. |

## Static analysis dispositions

The first Slither run analysed 60 contracts with 100 detectors and reported 72 findings: no high-severity findings, nine medium, fourteen low and forty-nine informational findings. This is the initial report, before the dead-helper removals and explicit zero initialisation. Findings were reviewed, not broadly suppressed.

| Medium finding | Condition and disposition |
| --- | --- |
| Exact balance equality in `Bridge.deposit` | The equality compares the actual token receipt with the declared deposit. Relaxing it accepts underfunded leaves. Intentional restriction to tokens with exact transfer semantics, exercised with a fee-token rollback test. |
| Exact balance equality in `StakeManager.stake` | The equality protects principal against fee-token underfunding. Intentional, exercised with an actual staking call and rollback assertions. |
| Default-zero proof accumulator | Solidity initialises local value types to zero, which was the intended non-existence accumulator. Initialisation is now explicit. Claims additionally require existence. |
| Ignored set-add result in `addValidator` | Registration has a separate status precondition. EnumerableSet membership insertion is idempotent; its return value describes whether the set changed, not whether insertion failed. Existing registration and membership tests exercise the public result. |
| Ignored set-add result in `updateValidatorStatus` | An active-to-active update deliberately retains membership. Requiring a changed set would reject an idempotent status update. |
| Ignored set-remove result in `updateValidatorStatus` | Every non-active status removes membership, including `Slashed`. An already absent member is the desired result. |
| Ignored set-remove result in `removeValidator` | Validators entering `Unstaking` have already been removed from the active set. Requiring this removal to change membership would break every normal full exit. |
| Missing return in `checkDepositExists` | Unused internal helper was removed, along with its unexercised return path. |
| Missing return in `checkClaimExists` | Unused internal helper was removed, along with its unexercised return path. |

Low-severity calls-in-loop findings identify a real unbounded validator/batch gas limitation. Callback and event findings cross owner-configured manager boundaries; replay state is set before slashing, but arbitrary manager replacement is a trusted administrative power. Timestamp findings cover intended cooldown, epoch and certificate validity rules. Initialisation permits an arbitrary verifier address and does not validate its code; deployment must select the verifier explicitly. Informational findings include project naming and intentional assembly. These dispositions do not establish production security.

## Verification

`forge clean` and `forge build` passed under Solidity 0.8.30. Full Foundry execution passed 110 tests in ten suites, with no failures or skips, using isolated local Anvil chains with IDs 1 and 8453 to match the checked-in BLS fixtures. `forge fmt --check` and the contract diff whitespace check passed.

The deterministic security suite uses real ERC20 transfers, UUPS proxies, validator-manager registration and BLS pairing through the standard scalar-one test key. Generated properties cover active/inactive exit conservation, jailed reactivation boundaries, claim ABI commitment, and principal/reward slash conservation. The security campaign ran 1,000 cases for the initial generated security properties; the full release campaign also passed all 110 tests with 1,000 fuzz cases per generated test. All project-owned source, script and test pragmas are pinned to Solidity 0.8.30.

Two temporary mutations were rejected by the intended tests: weakening the claim commitment and restoring the reserve-spending sweep precondition. Files were restored before the passing run.

OpenZeppelin validation requires full build metadata and a locally installed, pinned upgrades CLI. Initial suite failures were caused by concurrent implicit npx installs, stale partial build metadata, a missing fixture-read permission, a zero-owner fixture, mismatched mocked proof roots, and an outdated inactive-exit state assertion. Each was repaired at the owning fixture or configuration boundary without relaxing production checks.

## Remaining protocol and operational risks

The owner can replace managers, issue validator certificates, upgrade contracts and rescue bridge assets. These administrative powers require an explicit deployment trust model.

Certificates and BLS messages bind selected chain and actor fields but omit the verifying contract address. Reuse across manager instances sharing an owner and validator key is not prevented. Changing signed domains requires a coordinated protocol and fixture update.

Pre-confirmations use the current active-validator count without a committee snapshot. Membership changes during a vote can change the effective threshold. Validator reward distribution and proof processing use loops without a documented maximum batch/committee size.

Receipt-root witnesses need an authenticated chain-header trust anchor before the proof constitutes trustless cross-chain verification. Token addresses and liquidity need a supported cross-chain mapping and token policy. Rebasing or changeable token-transfer behaviour is outside the exact-receipt model.

Independent Rust/Solidity review identified that the Rust prover output included bad-root attestations while Solidity correctly rejects finalisation batches containing them. The canonical output must keep slash evidence separate from accepted attestations. Its final resolution and cross-language regression are recorded with the Rust change.

## Primary references

The [Solidity 0.8.30 ABI specification](https://docs.soliditylang.org/en/v0.8.30/abi-spec.html) defines the struct-as-tuple encoding used by the corrected commitment. [OpenZeppelin upgrade guidance](https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable) explains storage gaps and initialisation constraints. Repository source and executable public-path regressions are the evidence for the accounting behaviour above.
