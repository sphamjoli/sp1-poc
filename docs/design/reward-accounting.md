# Reserve validator rewards before withdrawal

Status: accepted for fresh local deployments. Date: 2026-10-07.

## Problem and observed behaviour

`StakeManager` previously mixed pending rewards into validator stake balances, credited rewards without reserving available funding, and allowed reserve sweeps without decrementing the reserve. Repeated sweeps could consume principal. Partial exits did not restore active status. Claim leaf hashing repeated the second struct field instead of committing every claim field.

## Required invariants

The token balance must cover total staked principal plus reward reserves. Reward reserves include already accrued rewards. Accrued rewards are tracked separately from principal and their total cannot exceed the reserve. Reward allocation either reserves the whole requested amount or reverts atomically. Payment decreases both the validator accrual and its backing reserve. A sweep removes only token balance above all liabilities.

Unstaking preserves pending rewards and reduces total principal by principal withdrawn. Partial unstaking restores the validator to Active when minimum principal remains. Top-ups cannot reset the original staking timestamp or alter an exit in progress. Token deposits must equal the amount actually received; fee-on-transfer tokens are rejected.

## Design and alternatives

Add an accrued-reward mapping in one reserved storage gap slot. Keep the existing reward reserve as the total funded reward pool, with an aggregate allocation check. This separates principal from rewards without introducing a second staking ledger.

Keeping rewards inside principal was rejected because it changes eligibility and makes full exits and reserve solvency ambiguous. Paying rewards immediately was rejected because recipient failure would couple reward allocation to token transfer availability.

Use structured ABI encoding for claim leaves rather than pointer assembly. Test every field against independent `abi.encode` vectors so source and destination commitments agree.

## Compatibility and rollout

These fixes target fresh local deployments. Existing validator balances may already include accrued rewards. The new mapping cannot reconstruct that split from storage alone; an existing funded deployment requires a separately reviewed migration and verified baseline layout. Do not apply the prototype's live upgrade command to populated stake contracts using this change.

Corrected claim hashing changes claim commitments. Outstanding claims built with the old malformed hash require a separate compatibility decision. Recreate local deployments and development assets rather than treating this as a transparent live upgrade.

## Verification

Use unit and fuzz tests for reserve exhaustion, repeated sweeps, accrued rewards, principal/reward exits, partial exit lifecycle, staking timestamp preservation, fee-on-transfer rejection and field-bound claim hashing. Run formatting, build and the complete Foundry suite. Mutation tests should restore the old hash or sweep behaviour and cause the new regressions to fail.

## Remaining trust gaps

This accounting correction does not establish authenticated chain roots, production owner governance, economic security or proof soundness in mock mode. Those remain explicit in `SECURITY.md` and `ARCHITECTURE.md`.
