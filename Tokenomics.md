# Tokenomics

This document explains the validator economics of the bridge in plain language. The intent is to help someone new to the system build the right mental model before reading the contracts.

## The short version

- Users bridge assets between Ethereum and Base.
- Validators are a separate layer. They stake on the base chain and earn rewards for correct work.
- In the default runtime, the base chain is Base (`31339`) and the validator staking token is `BBTA`.
- A validator needs at least `200 BBTA` to be active.
- Rewards are credited internally each epoch, but they are only claimable if the reward reserve has been funded.
- Slashing takes value from the offending validator and moves that value into the reward reserve.

If you remember one thing, remember this: bridge liquidity and validator economics are related operationally, but they are not the same pool of money.

## What the system is trying to optimize

The bridge wants validators to care about two things at the same time:

- staying honest because bad behavior is expensive
- staying online because useful work is rewarded

The design is intentionally simple for a POC. It does not try to solve every monetary-policy question. It tries to make the incentives legible enough that bridge behavior can be tested under realistic conditions.

## Where staking lives

Validator economics are anchored to the base chain.

- The runtime config sets `base_chain_id` to `31339`.
- Validators stake through the base-chain `StakeManager`.
- The active staking token in the default runtime is the base-chain token A, `BBTA`.
- Rewards, reserve top-ups, claims, slashing, and exits are all settled there.

That means a validator can attest across supported chains, but the economic consequences are still enforced in one place.

## Becoming active

To become active, a validator stakes `BBTA` and proves ownership of its BLS key.

Important thresholds in the default runtime:

- Minimum stake: `200 BBTA`
- Minimum partial unstake amount: `1 BBTA`
- Standard unstake delay: `604800` seconds, which is 7 days
- Slashing rate parameter in config: `10`

If a validator is already known to the system and tops its stake back up above the minimum, it can return to `Active`.

## How rewards are funded

There are two separate steps.

First, the owner funds the reward reserve.

- The owner transfers reward tokens into `StakeManager` through `transferToken`.
- In practice this is exposed through node-manager and the Bridge Health UI.
- Without reserve funding, rewards can be calculated but not claimed.

Second, the owner distributes rewards for the epoch.

- `ValidatorManager.distributeRewards()` is `onlyOwner`.
- That call passes the current epoch and validator set into `StakeManager.distributeRewards()`.
- Distribution credits each eligible validator's internal reward balance.
- Claiming is a separate action that later moves tokens from the reserve to the validator wallet.

This separation is important. Distribution creates an entitlement. Reserve funding makes that entitlement payable.

## Who is eligible for rewards

A validator does not earn rewards just because it exists.

To be eligible in an epoch, it must:

- still be `Active`
- have at least the minimum active stake
- not have already been rewarded in the same epoch
- maintain at least `80%` performance for the measured attestations in that epoch

Performance is computed as:

```text
performanceScore = correctAttestations / totalAttestations
```

Internally, the contract scales that ratio by `10_000`, so the minimum threshold is `8_000`.

## How the epoch reward pool is computed

The base annual reward rate is `500` basis points, which is `5%`.

The contract starts with an annualized epoch reward:

```text
epochReward = totalStaked * 500 / (10_000 * epochsPerYear)
```

Then it applies a dampening step:

```text
scalingFactor = sqrt(totalStaked / 1_000_000)
```

If that scaling factor is greater than `1`, the epoch reward is divided by it. After that, the pool is clamped into a floor and a ceiling:

```text
minimumEpochReward = totalStaked / 1_000_000
maximumEpochReward = totalStaked / 10_000
```

The effect is straightforward:

- very small validator sets still get a non-zero reward floor
- very large validator sets do not explode rewards linearly forever
- total rewards grow more slowly as stake becomes very large

## How an individual validator's share is computed

Each eligible validator gets points. More stake helps, but useful work also matters.

```text
points = (stakeAmount / 1e18) + (correctAttestations * 10)
```

That means:

- stake contributes one point per whole token
- each correct attestation adds ten extra points

The validator's base share of the epoch pool is then:

```text
validatorReward = rewardPool * validatorPoints / totalEligiblePoints
```

After that, an early-validator bonus may be added.

## Early validator bonus

Early validators get an extra bonus that decays linearly over time.

- Initial bonus amount: `1 token`
- Bonus window: `12,960` epochs

The formula is:

```text
earlyBonus = 1 token * remainingEarlyEpochs / 12_960
```

This is a simple bootstrapping mechanism. It rewards validators that joined early without locking the system into a permanent early-adopter advantage.

## Claiming rewards

When rewards are distributed, they increase the validator's internal `balance` inside `StakeManager`.

That does not automatically transfer tokens out.

To receive the tokens, the validator later calls `claimRewards()`. That claim only succeeds if the reserve has enough of the staking token to cover the amount. If the reserve is underfunded, the entitlement exists but the payout cannot complete yet.

This is why reserve top-ups matter operationally.

## How slashing works

Slashing is now deliberately conservative.

- Only active validators can be slashed.
- Replayed finalization batches are rejected before they can reslash the same offense.
- Scenario tooling refuses to slash a non-active validator unless you explicitly force it.

When a slash happens, the contract removes value in this order:

1. principal stake first, if enough exists
2. pending unclaimed rewards next, if needed

The slashed amount is moved into the reward reserve. So slashing does not destroy value inside the POC economy. It redistributes value away from bad validators and toward the pool that honest validators can later claim from.

If a slash pushes remaining stake below the active minimum:

- the validator becomes `Inactive`
- it is no longer slashable
- it can move toward exit instead of being punished indefinitely

That behavior matters because repeated punishment after the validator is already inactive does not improve safety. It only creates accounting noise and replay risk.

## Unstaking and withdrawal

There are two broad paths.

Active validator exit:

- a validator begins partial or full unstaking
- the system starts the configured cooldown
- after the delay, the validator completes the unstake

Slashed or inactive validator exit:

- if slashing already pushed the validator below minimum, the validator is marked inactive
- the slashing path sets the exit timestamp immediately
- the validator can move into the unstake flow and exit without waiting for a new 7-day delay

This is useful in a testbed because it keeps recovery and failure scenarios easy to reason about.

## What a bridge user should take away

If you are using the bridge rather than operating a validator, the main thing to understand is that validator rewards do not come out of your transferred funds directly.

Your transfer depends on:

- bridge liquidity
- validator attestations
- destination-chain claimability
- later SP1 settlement

Validator rewards depend on:

- base-chain stake
- epoch distribution by the owner
- reserve funding
- validator performance

Those layers interact, but they are not the same accounting bucket.

## What is intentionally unfinished

This is still a POC.

- Reward policy is simple and easy to inspect, not final.
- Reserve funding is manual today.
- Reward indexing is being moved toward the indexer so the UI can rely less on live runtime aggregation.
- The design is meant to surface trade-offs, not hide them.

That is a feature in a research prototype. The point is to make the economics understandable enough that the failure modes can be exercised on a live bridge.
