use alloy::{
    primitives::{Address, B256, U256},
    providers::{DynProvider, Provider},
    rpc::types::{BlockNumberOrTag, TransactionReceipt},
    sol_types::SolCall,
};
use clap::{Parser, Subcommand};
use eyre::{bail, eyre, Result, WrapErr};
use jsonrpsee::{core::client::ClientT, http_client::HttpClientBuilder, rpc_params};
use serde::Serialize;
use serde_json::{json, Value};
use std::{fs, path::PathBuf, time::Duration};
use tokio::time::sleep;
use validator_utils::{
    bindings::{
        BlsOwnerShip, IStakeManager, IValidatorManager, SlashParams, StakeManagerConfig,
        StakeParams, UnstakingParams, ValidatorBalance, IERC20,
    },
    ensure_successful_receipt, parse_u256_hex_or_decimal,
    providers::{read_provider, signer_provider},
    ChainConfig, DevValidator, LoadedRuntime, DEFAULT_RUNTIME_CONFIG,
};

const IMPERSONATED_BALANCE_WEI: u128 = 10_000_000_000_000_000_000u128;

#[derive(Debug, Parser)]
#[command(name = "live-scenarios")]
#[command(about = "Trigger live validator and staking scenarios against the running bridge")]
struct CommandLineInterface {
    #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG, env = "RUNTIME_CONFIG")]
    config: String,
    #[arg(long)]
    json_out: Option<PathBuf>,
    #[command(subcommand)]
    command: ScenarioCommand,
}

#[derive(Debug, Subcommand)]
enum ScenarioCommand {
    Slash {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        amount_wei: String,
        #[arg(long, default_value_t = false)]
        force: bool,
    },
    Jail {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long, default_value_t = false)]
        force: bool,
    },
    Recover {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        amount_wei: Option<String>,
    },
    JailRecover {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        amount_wei: Option<String>,
        #[arg(long, default_value_t = false)]
        force: bool,
    },
    BeginUnstake {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        amount_wei: String,
    },
    CompleteUnstake {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        fast_forward: bool,
    },
    PartialUnstake {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        amount_wei: Option<String>,
        #[arg(long)]
        fast_forward: bool,
    },
    FullUnstake {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        fast_forward: bool,
    },
    ClaimRewards {
        #[arg(long, default_value = "alice")]
        validator: String,
    },
    SlashedExit {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long)]
        fast_forward: bool,
        #[arg(long, default_value_t = false)]
        force: bool,
    },
    JailNoRewards {
        #[arg(long, default_value = "alice")]
        validator: String,
        #[arg(long, default_value_t = false)]
        force: bool,
    },
    DistributeRewards,
    Warp {
        #[arg(long)]
        seconds: u64,
        #[arg(long)]
        chain_id: Option<u64>,
    },
}

#[derive(Debug, Serialize)]
struct ScenarioReport {
    action: String,
    #[serde(rename = "chainId")]
    chain_id: u64,
    validator: Option<String>,
    #[serde(rename = "validatorAddress")]
    validator_address: Option<Address>,
    #[serde(rename = "stakeManager")]
    stake_manager: Option<Address>,
    #[serde(rename = "validatorManager")]
    validator_manager: Option<Address>,
    #[serde(rename = "txHashes")]
    tx_hashes: Vec<String>,
    before: Option<ValidatorSnapshot>,
    after: Option<ValidatorSnapshot>,
    details: Value,
}

#[derive(Debug, Clone, Serialize)]
struct ValidatorSnapshot {
    status: String,
    #[serde(rename = "stakeAmountWei")]
    stake_amount_wei: String,
    #[serde(rename = "pendingRewardsWei")]
    pending_rewards_wei: String,
    #[serde(rename = "unstakeAmountWei")]
    unstake_amount_wei: String,
    #[serde(rename = "stakeExitTimestamp")]
    stake_exit_timestamp: String,
    #[serde(rename = "attestationCount")]
    attestation_count: String,
    #[serde(rename = "invalidAttestations")]
    invalid_attestations: String,
    #[serde(rename = "lastRewardEpoch")]
    last_reward_epoch: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt().with_target(false).init();

    let command_line_interface = CommandLineInterface::parse();
    let runtime = LoadedRuntime::load(&command_line_interface.config)?;
    let report = execute_scenario(&runtime, command_line_interface.command).await?;

    if let Some(json_out) = command_line_interface.json_out {
        if let Some(parent_directory) = json_out.parent() {
            fs::create_dir_all(parent_directory)
                .wrap_err_with(|| format!("failed to create {}", parent_directory.display()))?;
        }
        fs::write(&json_out, serde_json::to_vec_pretty(&report)?)
            .wrap_err_with(|| format!("failed to write {}", json_out.display()))?;
    }

    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}

async fn execute_scenario(
    runtime: &LoadedRuntime,
    command: ScenarioCommand,
) -> Result<ScenarioReport> {
    match command {
        ScenarioCommand::Slash { validator, amount_wei, force } => {
            run_slash(runtime, &validator, parse_u256_hex_or_decimal(&amount_wei)?, force).await
        }
        ScenarioCommand::Jail { validator, force } => run_jail(runtime, &validator, force).await,
        ScenarioCommand::Recover { validator, amount_wei } => {
            let parsed_amount = amount_wei.as_deref().map(parse_u256_hex_or_decimal).transpose()?;
            run_recover(runtime, &validator, parsed_amount).await
        }
        ScenarioCommand::JailRecover { validator, amount_wei, force } => {
            let parsed_amount = amount_wei.as_deref().map(parse_u256_hex_or_decimal).transpose()?;
            run_jail_recover(runtime, &validator, parsed_amount, force).await
        }
        ScenarioCommand::BeginUnstake { validator, amount_wei } => {
            run_begin_unstake(runtime, &validator, parse_u256_hex_or_decimal(&amount_wei)?).await
        }
        ScenarioCommand::CompleteUnstake { validator, fast_forward } => {
            run_complete_unstake(runtime, &validator, fast_forward).await
        }
        ScenarioCommand::PartialUnstake { validator, amount_wei, fast_forward } => {
            let parsed_amount = amount_wei.as_deref().map(parse_u256_hex_or_decimal).transpose()?;
            run_partial_unstake(runtime, &validator, parsed_amount, fast_forward).await
        }
        ScenarioCommand::FullUnstake { validator, fast_forward } => {
            run_full_unstake(runtime, &validator, fast_forward).await
        }
        ScenarioCommand::ClaimRewards { validator } => run_claim_rewards(runtime, &validator).await,
        ScenarioCommand::SlashedExit { validator, fast_forward, force } => {
            run_slashed_exit(runtime, &validator, fast_forward, force).await
        }
        ScenarioCommand::JailNoRewards { validator, force } => {
            run_jail_no_rewards(runtime, &validator, force).await
        }
        ScenarioCommand::DistributeRewards => run_distribute_rewards(runtime).await,
        ScenarioCommand::Warp { seconds, chain_id } => run_warp(runtime, chain_id, seconds).await,
    }
}

async fn run_slash(
    runtime: &LoadedRuntime,
    validator_name: &str,
    amount: U256,
    force: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    ensure_validator_can_be_slashed(&before, &context, force)?;
    let receipt = slash_validator(&context, amount).await?;
    let after = context.snapshot().await?;

    Ok(context.report(
        "slash",
        vec![receipt.transaction_hash.to_string()],
        Some(before),
        Some(after),
        json!({
            "slashAmountWei": amount.to_string(),
            "forced": force,
        }),
    )?)
}

async fn run_jail(
    runtime: &LoadedRuntime,
    validator_name: &str,
    force: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    ensure_validator_can_be_slashed(&before, &context, force)?;
    let amount = compute_jailing_slash_amount(&context).await?;
    let receipt = slash_validator(&context, amount).await?;
    let after = context.snapshot().await?;

    Ok(context.report(
        "jail",
        vec![receipt.transaction_hash.to_string()],
        Some(before),
        Some(after),
        json!({
            "slashAmountWei": amount.to_string(),
            "expectedStatus": "Inactive",
            "forced": force,
        }),
    )?)
}

async fn run_recover(
    runtime: &LoadedRuntime,
    validator_name: &str,
    amount_override: Option<U256>,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    let active_config = context.active_config().await?;
    let amount = amount_override.unwrap_or(active_config.minStakeAmount);

    let fund_receipt = ensure_validator_has_staking_tokens(&context, amount).await?;
    let approve_receipt =
        approve_staking_tokens(&context, active_config.stakingToken, amount).await?;
    let stake_receipt = restake_validator(&context, active_config, amount).await?;
    let after = context.snapshot().await?;

    let mut tx_hashes = Vec::new();
    if let Some(receipt) = fund_receipt {
        tx_hashes.push(receipt.transaction_hash.to_string());
    }
    tx_hashes.push(approve_receipt.transaction_hash.to_string());
    tx_hashes.push(stake_receipt.transaction_hash.to_string());

    Ok(context.report(
        "recover",
        tx_hashes,
        Some(before),
        Some(after),
        json!({
            "restakeAmountWei": amount.to_string(),
        }),
    )?)
}

async fn run_jail_recover(
    runtime: &LoadedRuntime,
    validator_name: &str,
    amount_override: Option<U256>,
    force: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    ensure_validator_can_be_slashed(&before, &context, force)?;
    let slash_amount = compute_jailing_slash_amount(&context).await?;
    let slash_receipt = slash_validator(&context, slash_amount).await?;

    let active_config = context.active_config().await?;
    let restake_amount = amount_override.unwrap_or(active_config.minStakeAmount);
    let fund_receipt = ensure_validator_has_staking_tokens(&context, restake_amount).await?;
    let approve_receipt =
        approve_staking_tokens(&context, active_config.stakingToken, restake_amount).await?;
    let stake_receipt = restake_validator(&context, active_config, restake_amount).await?;
    let after = context.snapshot().await?;

    let mut tx_hashes = vec![slash_receipt.transaction_hash.to_string()];
    if let Some(receipt) = fund_receipt {
        tx_hashes.push(receipt.transaction_hash.to_string());
    }
    tx_hashes.push(approve_receipt.transaction_hash.to_string());
    tx_hashes.push(stake_receipt.transaction_hash.to_string());

    Ok(context.report(
        "jail-recover",
        tx_hashes,
        Some(before),
        Some(after),
        json!({
            "slashAmountWei": slash_amount.to_string(),
            "restakeAmountWei": restake_amount.to_string(),
            "forced": force,
        }),
    )?)
}

async fn run_begin_unstake(
    runtime: &LoadedRuntime,
    validator_name: &str,
    amount: U256,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    let receipt = begin_unstaking(&context, amount).await?;
    let after = context.snapshot().await?;

    Ok(context.report(
        "begin-unstake",
        vec![receipt.transaction_hash.to_string()],
        Some(before),
        Some(after),
        json!({
            "unstakeAmountWei": amount.to_string(),
        }),
    )?)
}

async fn run_complete_unstake(
    runtime: &LoadedRuntime,
    validator_name: &str,
    fast_forward: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    let balance_before = context.validator_balance().await?;
    let advanced_seconds = if fast_forward && balance_before.stakeExitTimestamp > U256::ZERO {
        advance_to_timestamp_if_needed(&context, balance_before.stakeExitTimestamp).await?
    } else {
        0
    };

    let receipt = complete_unstaking(&context).await?;
    let after = context.snapshot().await.ok();

    Ok(context.report(
        "complete-unstake",
        vec![receipt.transaction_hash.to_string()],
        Some(before),
        after,
        json!({
            "fastForwarded": fast_forward,
            "advancedSeconds": advanced_seconds,
        }),
    )?)
}

async fn run_partial_unstake(
    runtime: &LoadedRuntime,
    validator_name: &str,
    amount_override: Option<U256>,
    fast_forward: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    let amount = partial_unstake_amount(&context, amount_override).await?;
    let begin_receipt = begin_unstaking(&context, amount).await?;
    let balance_after_begin = context.validator_balance().await?;
    let advanced_seconds = if fast_forward && balance_after_begin.stakeExitTimestamp > U256::ZERO {
        advance_to_timestamp_if_needed(&context, balance_after_begin.stakeExitTimestamp).await?
    } else {
        0
    };

    let mut tx_hashes = vec![begin_receipt.transaction_hash.to_string()];
    if fast_forward {
        let complete_receipt = complete_unstaking(&context).await?;
        tx_hashes.push(complete_receipt.transaction_hash.to_string());
    }
    let after = context.snapshot().await.ok();

    Ok(context.report(
        "partial-unstake",
        tx_hashes,
        Some(before),
        after,
        json!({
            "unstakeAmountWei": amount.to_string(),
            "fastForwarded": fast_forward,
            "advancedSeconds": advanced_seconds,
        }),
    )?)
}

async fn run_full_unstake(
    runtime: &LoadedRuntime,
    validator_name: &str,
    fast_forward: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    let balance_before = context.validator_balance().await?;
    if balance_before.stakeAmount.is_zero() {
        bail!("validator {} has no stake to unstake", context.validator.name);
    }

    let begin_receipt = begin_unstaking(&context, balance_before.stakeAmount).await?;
    let balance_after_begin = context.validator_balance().await?;
    let advanced_seconds = if fast_forward && balance_after_begin.stakeExitTimestamp > U256::ZERO {
        advance_to_timestamp_if_needed(&context, balance_after_begin.stakeExitTimestamp).await?
    } else {
        0
    };

    let mut tx_hashes = vec![begin_receipt.transaction_hash.to_string()];
    if fast_forward {
        let complete_receipt = complete_unstaking(&context).await?;
        tx_hashes.push(complete_receipt.transaction_hash.to_string());
    }
    let after = context.snapshot().await.ok();

    Ok(context.report(
        "full-unstake",
        tx_hashes,
        Some(before),
        after,
        json!({
            "unstakeAmountWei": balance_before.stakeAmount.to_string(),
            "fastForwarded": fast_forward,
            "advancedSeconds": advanced_seconds,
        }),
    )?)
}

async fn run_claim_rewards(
    runtime: &LoadedRuntime,
    validator_name: &str,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    let mut tx_hashes = Vec::new();

    let mut pending_rewards = context.latest_rewards().await?;
    let distribution_receipt = if pending_rewards.is_zero() {
        distribute_rewards_if_needed(&context).await?
    } else {
        None
    };
    let distribution_triggered = distribution_receipt.is_some();
    if let Some(receipt) = distribution_receipt {
        tx_hashes.push(receipt.transaction_hash.to_string());
        pending_rewards = context.latest_rewards().await?;
    }

    if pending_rewards.is_zero() {
        bail!(
            "validator {} has no pending rewards to claim; advance a real bridge epoch first",
            context.validator.name
        );
    }

    let receipt = claim_rewards(&context).await?;
    tx_hashes.push(receipt.transaction_hash.to_string());
    let after = context.snapshot().await?;

    Ok(context.report(
        "claim-rewards",
        tx_hashes,
        Some(before),
        Some(after),
        json!({
            "claimedRewardWei": pending_rewards.to_string(),
            "distributionTriggered": distribution_triggered,
        }),
    )?)
}

async fn run_slashed_exit(
    runtime: &LoadedRuntime,
    validator_name: &str,
    fast_forward: bool,
    force: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    ensure_validator_can_be_slashed(&before, &context, force)?;
    let slash_amount = compute_jailing_slash_amount(&context).await?;
    let slash_receipt = slash_validator(&context, slash_amount).await?;
    let balance_after_slash = context.validator_balance().await?;
    let begin_receipt = begin_unstaking(&context, balance_after_slash.stakeAmount).await?;
    let balance_after_begin = context.validator_balance().await?;

    let advanced_seconds = if fast_forward && balance_after_begin.stakeExitTimestamp > U256::ZERO {
        advance_to_timestamp_if_needed(&context, balance_after_begin.stakeExitTimestamp).await?
    } else {
        0
    };

    let mut tx_hashes = vec![
        slash_receipt.transaction_hash.to_string(),
        begin_receipt.transaction_hash.to_string(),
    ];
    if fast_forward {
        let complete_receipt = complete_unstaking(&context).await?;
        tx_hashes.push(complete_receipt.transaction_hash.to_string());
    }
    let after = context.snapshot().await.ok();

    Ok(context.report(
        "slashed-exit",
        tx_hashes,
        Some(before),
        after,
        json!({
            "slashAmountWei": slash_amount.to_string(),
            "fastForwarded": fast_forward,
            "advancedSeconds": advanced_seconds,
            "forced": force,
        }),
    )?)
}

async fn run_jail_no_rewards(
    runtime: &LoadedRuntime,
    validator_name: &str,
    force: bool,
) -> Result<ScenarioReport> {
    let context = ValidatorContext::load(runtime, validator_name).await?;
    let before = context.snapshot().await?;
    ensure_validator_can_be_slashed(&before, &context, force)?;
    let rewards_before = context.latest_rewards().await?;
    let slash_amount = compute_jailing_slash_amount(&context).await?;
    let slash_receipt = slash_validator(&context, slash_amount).await?;
    let distribution_receipt = distribute_rewards_if_needed(&context).await?;
    let rewards_after = context.latest_rewards().await?;

    if distribution_receipt.is_some() && rewards_after > rewards_before {
        bail!("jailed validator {} unexpectedly accrued new rewards", context.validator.name);
    }

    let mut tx_hashes = vec![slash_receipt.transaction_hash.to_string()];
    if let Some(receipt) = &distribution_receipt {
        tx_hashes.push(receipt.transaction_hash.to_string());
    }
    let after = context.snapshot().await?;

    Ok(context.report(
        "jail-no-rewards",
        tx_hashes,
        Some(before),
        Some(after),
        json!({
            "slashAmountWei": slash_amount.to_string(),
            "distributionTriggered": distribution_receipt.is_some(),
            "pendingRewardsBeforeWei": rewards_before.to_string(),
            "pendingRewardsAfterWei": rewards_after.to_string(),
            "forced": force,
        }),
    )?)
}

async fn run_distribute_rewards(runtime: &LoadedRuntime) -> Result<ScenarioReport> {
    let base_chain = runtime.base_chain()?;
    let base_deploy = runtime.deployment(base_chain.id)?;
    let read = read_provider(base_chain).await?;
    let owner = signer_provider(base_chain, runtime.owner_signer()?).await?;
    let validator_manager_reader =
        IValidatorManager::new(base_deploy.validator_manager, read.clone());
    let stake_manager_reader = IStakeManager::new(base_deploy.stake_manager, read);
    let current_epoch =
        validator_manager_reader.EPOCH().call().await.wrap_err("failed to read current epoch")?;

    let should_distribute =
        rewards_need_distribution(&validator_manager_reader, &stake_manager_reader, current_epoch)
            .await?;
    let mut tx_hashes = Vec::new();
    if should_distribute {
        let receipt = IValidatorManager::new(base_deploy.validator_manager, owner)
            .distributeRewards()
            .send()
            .await
            .wrap_err("failed to distribute rewards")?
            .get_receipt()
            .await
            .wrap_err("failed waiting for reward distribution receipt")?;
        ensure_successful_receipt("reward distribution", &receipt)?;
        tx_hashes.push(receipt.transaction_hash.to_string());
    }

    Ok(ScenarioReport {
        action: "distribute-rewards".to_owned(),
        chain_id: base_chain.id,
        validator: None,
        validator_address: None,
        stake_manager: Some(base_deploy.stake_manager),
        validator_manager: Some(base_deploy.validator_manager),
        tx_hashes,
        before: None,
        after: None,
        details: json!({
            "currentEpoch": current_epoch.to_string(),
            "distributionTriggered": should_distribute,
        }),
    })
}

async fn run_warp(
    runtime: &LoadedRuntime,
    chain_id: Option<u64>,
    seconds: u64,
) -> Result<ScenarioReport> {
    let target_chain_id = chain_id.unwrap_or(runtime.config.base_chain_id);
    let chain = runtime.chain(target_chain_id)?;
    let timestamp_before = current_block_timestamp(chain).await?;
    let advanced_seconds = advance_time_on_chain(&chain.rpc_url, seconds).await?;
    let timestamp_after = current_block_timestamp(chain).await?;

    Ok(ScenarioReport {
        action: "warp".to_owned(),
        chain_id: target_chain_id,
        validator: None,
        validator_address: None,
        stake_manager: None,
        validator_manager: None,
        tx_hashes: Vec::new(),
        before: None,
        after: None,
        details: json!({
            "advancedSeconds": advanced_seconds,
            "timestampBefore": timestamp_before,
            "timestampAfter": timestamp_after,
        }),
    })
}

struct ValidatorContext<'runtime> {
    validator: &'runtime DevValidator,
    base_chain: &'runtime ChainConfig,
    base_chain_id: u64,
    stake_manager_address: Address,
    validator_manager_address: Address,
    read_provider: DynProvider,
    validator_provider: DynProvider,
    owner_provider: DynProvider,
}

impl<'runtime> ValidatorContext<'runtime> {
    async fn load(runtime: &'runtime LoadedRuntime, validator_name: &str) -> Result<Self> {
        let validator = runtime.validator_catalog.by_name(validator_name)?;
        let base_chain = runtime.base_chain()?;
        let base_deploy = runtime.deployment(base_chain.id)?;
        let read_provider = read_provider(base_chain).await?;
        ensure_contract_code(
            &read_provider,
            base_deploy.validator_manager,
            "validator manager",
            runtime,
            base_chain,
        )
        .await?;
        ensure_contract_code(
            &read_provider,
            base_deploy.stake_manager,
            "stake manager",
            runtime,
            base_chain,
        )
        .await?;
        let validator_provider = signer_provider(base_chain, validator.evm_signer()?).await?;
        let owner_provider = signer_provider(base_chain, runtime.owner_signer()?).await?;

        Ok(Self {
            validator,
            base_chain,
            base_chain_id: base_chain.id,
            stake_manager_address: base_deploy.stake_manager,
            validator_manager_address: base_deploy.validator_manager,
            read_provider,
            validator_provider,
            owner_provider,
        })
    }

    fn stake_manager_reader(&self) -> IStakeManager::IStakeManagerInstance<DynProvider> {
        IStakeManager::new(self.stake_manager_address, self.read_provider.clone())
    }

    fn stake_manager_as_validator(&self) -> IStakeManager::IStakeManagerInstance<DynProvider> {
        IStakeManager::new(self.stake_manager_address, self.validator_provider.clone())
    }

    fn validator_manager_reader(
        &self,
    ) -> IValidatorManager::IValidatorManagerInstance<DynProvider> {
        IValidatorManager::new(self.validator_manager_address, self.read_provider.clone())
    }

    fn validator_manager_as_owner(
        &self,
    ) -> IValidatorManager::IValidatorManagerInstance<DynProvider> {
        IValidatorManager::new(self.validator_manager_address, self.owner_provider.clone())
    }

    async fn snapshot(&self) -> Result<ValidatorSnapshot> {
        let validator_address = self.validator.address()?;
        let info = self
            .validator_manager_reader()
            .getValidator(validator_address)
            .call()
            .await
            .wrap_err("failed to read validator info")?;
        let balance = self.validator_balance().await?;

        Ok(ValidatorSnapshot {
            status: validator_status_label(info.status).to_owned(),
            stake_amount_wei: balance.stakeAmount.to_string(),
            pending_rewards_wei: balance.balance.to_string(),
            unstake_amount_wei: balance.unstakeAmount.to_string(),
            stake_exit_timestamp: balance.stakeExitTimestamp.to_string(),
            attestation_count: info.attestationCount.to_string(),
            invalid_attestations: info.invalidAttestations.to_string(),
            last_reward_epoch: balance.lastRewardEpoch.to_string(),
        })
    }

    async fn validator_balance(&self) -> Result<ValidatorBalance> {
        self.stake_manager_reader()
            .validatorBalance(self.validator.address()?)
            .call()
            .await
            .wrap_err("failed to read validator balance")
    }

    async fn latest_rewards(&self) -> Result<U256> {
        self.stake_manager_reader()
            .getLatestRewards(self.validator.address()?)
            .call()
            .await
            .wrap_err("failed to read validator pending rewards")
    }

    async fn active_config(&self) -> Result<StakeManagerConfig> {
        self.stake_manager_reader()
            .ACTIVE_STAKING_CONFIG()
            .call()
            .await
            .wrap_err("failed to read active staking config")
    }

    fn report(
        &self,
        action: &str,
        tx_hashes: Vec<String>,
        before: Option<ValidatorSnapshot>,
        after: Option<ValidatorSnapshot>,
        details: Value,
    ) -> Result<ScenarioReport> {
        Ok(ScenarioReport {
            action: action.to_owned(),
            chain_id: self.base_chain_id,
            validator: Some(self.validator.name.clone()),
            validator_address: Some(self.validator.address()?),
            stake_manager: Some(self.stake_manager_address),
            validator_manager: Some(self.validator_manager_address),
            tx_hashes,
            before,
            after,
            details,
        })
    }
}

async fn compute_jailing_slash_amount(context: &ValidatorContext<'_>) -> Result<U256> {
    let balance = context.validator_balance().await?;
    let active_config = context.active_config().await?;

    if balance.stakeAmount <= active_config.minStakeAmount {
        bail!(
            "validator {} already has stake {} at or below minimum {}",
            context.validator.name,
            balance.stakeAmount,
            active_config.minStakeAmount
        );
    }

    Ok(balance.stakeAmount - active_config.minStakeAmount + U256::from(1))
}

fn ensure_validator_can_be_slashed(
    snapshot: &ValidatorSnapshot,
    context: &ValidatorContext<'_>,
    force: bool,
) -> Result<()> {
    validate_slashable_status(snapshot.status.as_str(), &context.validator.name, force)
}

fn validate_slashable_status(status: &str, validator_name: &str, force: bool) -> Result<()> {
    if force || status == "Active" {
        return Ok(());
    }

    bail!(
        "validator {} is {}. refusing to slash a non-active validator without --force",
        validator_name,
        status
    );
}

async fn partial_unstake_amount(
    context: &ValidatorContext<'_>,
    amount_override: Option<U256>,
) -> Result<U256> {
    let balance = context.validator_balance().await?;
    let active_config = context.active_config().await?;
    if balance.stakeAmount.is_zero() {
        bail!("validator {} has no stake to unstake", context.validator.name);
    }

    if let Some(amount) = amount_override {
        return Ok(amount);
    }

    let mut amount = balance.stakeAmount / U256::from(2);
    if amount <= active_config.minWithdrawAmount {
        amount = active_config.minWithdrawAmount + U256::from(1);
    }
    if amount >= balance.stakeAmount {
        bail!(
            "validator {} does not have enough stake for an automatic partial unstake; pass --amount-wei explicitly",
            context.validator.name
        );
    }

    let remaining = balance.stakeAmount - amount;
    if remaining < active_config.minStakeAmount {
        amount = balance.stakeAmount - active_config.minStakeAmount;
    }
    if amount.is_zero()
        || amount <= active_config.minWithdrawAmount
        || amount >= balance.stakeAmount
    {
        bail!(
            "unable to derive a valid partial unstake amount for {}; pass --amount-wei explicitly",
            context.validator.name
        );
    }

    Ok(amount)
}

async fn slash_validator(
    context: &ValidatorContext<'_>,
    amount: U256,
) -> Result<TransactionReceipt> {
    let call_data = IStakeManager::slashValidatorCall {
        params: SlashParams { validator: context.validator.address()?, slashAmount: amount },
    }
    .abi_encode();

    impersonated_call(
        context.base_chain,
        context.validator_manager_address,
        context.stake_manager_address,
        call_data,
    )
    .await
}

async fn ensure_validator_has_staking_tokens(
    context: &ValidatorContext<'_>,
    amount: U256,
) -> Result<Option<TransactionReceipt>> {
    let active_config = context.active_config().await?;
    let token = IERC20::new(active_config.stakingToken, context.owner_provider.clone());
    let validator_balance = token
        .balanceOf(context.validator.address()?)
        .call()
        .await
        .wrap_err("failed to read validator staking token balance")?;
    if validator_balance >= amount {
        return Ok(None);
    }

    let funding_amount = amount - validator_balance;
    let receipt = token
        .transfer(context.validator.address()?, funding_amount)
        .send()
        .await
        .wrap_err("failed to fund validator staking balance")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for validator funding receipt")?;
    ensure_successful_receipt("fund validator staking balance", &receipt)?;
    Ok(Some(receipt))
}

async fn approve_staking_tokens(
    context: &ValidatorContext<'_>,
    token_address: Address,
    amount: U256,
) -> Result<TransactionReceipt> {
    let token = IERC20::new(token_address, context.validator_provider.clone());
    let receipt = token
        .approve(context.stake_manager_address, amount)
        .send()
        .await
        .wrap_err("failed to approve staking token spend")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for staking approve receipt")?;
    ensure_successful_receipt("approve staking token spend", &receipt)?;
    Ok(receipt)
}

async fn restake_validator(
    context: &ValidatorContext<'_>,
    active_config: StakeManagerConfig,
    amount: U256,
) -> Result<TransactionReceipt> {
    let stake_version = context
        .stake_manager_reader()
        .getStakeVersion(active_config.clone())
        .call()
        .await
        .wrap_err("failed to compute stake version")?;
    let proof = BlsOwnerShip {
        signature: context.validator.stake_pop_signature(context.base_chain_id)?,
        pubkey: context.validator.bls_public_key_words()?,
    };
    let receipt = context
        .stake_manager_as_validator()
        .stake(StakeParams { stakeAmount: amount, stakeVersion: stake_version }, proof)
        .send()
        .await
        .wrap_err("failed to restake validator")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for restake receipt")?;
    ensure_successful_receipt("restake validator", &receipt)?;
    Ok(receipt)
}

async fn begin_unstaking(
    context: &ValidatorContext<'_>,
    amount: U256,
) -> Result<TransactionReceipt> {
    let receipt = context
        .stake_manager_as_validator()
        .beginUnstaking(UnstakingParams { stakeAmount: amount })
        .send()
        .await
        .wrap_err("failed to begin unstaking")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for begin unstaking receipt")?;
    ensure_successful_receipt("begin unstaking", &receipt)?;
    Ok(receipt)
}

async fn complete_unstaking(context: &ValidatorContext<'_>) -> Result<TransactionReceipt> {
    let receipt = context
        .stake_manager_as_validator()
        .completeUnstaking()
        .send()
        .await
        .wrap_err("failed to complete unstaking")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for complete unstaking receipt")?;
    ensure_successful_receipt("complete unstaking", &receipt)?;
    Ok(receipt)
}

async fn claim_rewards(context: &ValidatorContext<'_>) -> Result<TransactionReceipt> {
    let receipt = context
        .stake_manager_as_validator()
        .claimRewards()
        .send()
        .await
        .wrap_err("failed to claim rewards")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for reward claim receipt")?;
    ensure_successful_receipt("claim rewards", &receipt)?;
    Ok(receipt)
}

async fn distribute_rewards_if_needed(
    context: &ValidatorContext<'_>,
) -> Result<Option<TransactionReceipt>> {
    let validator_manager = context.validator_manager_reader();
    let stake_manager = context.stake_manager_reader();
    let current_epoch =
        validator_manager.EPOCH().call().await.wrap_err("failed to read current epoch")?;
    let should_distribute =
        rewards_need_distribution(&validator_manager, &stake_manager, current_epoch).await?;
    if !should_distribute {
        return Ok(None);
    }

    let receipt = context
        .validator_manager_as_owner()
        .distributeRewards()
        .send()
        .await
        .wrap_err("failed to distribute rewards")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for reward distribution receipt")?;
    ensure_successful_receipt("reward distribution", &receipt)?;
    Ok(Some(receipt))
}

async fn rewards_need_distribution(
    validator_manager: &IValidatorManager::IValidatorManagerInstance<DynProvider>,
    stake_manager: &IStakeManager::IStakeManagerInstance<DynProvider>,
    current_epoch: U256,
) -> Result<bool> {
    let active_validators = validator_manager
        .getActiveValidators()
        .call()
        .await
        .wrap_err("failed to read active validators")?;
    if active_validators.is_empty() {
        return Ok(false);
    }

    for validator in active_validators {
        let balance = stake_manager
            .validatorBalance(validator)
            .call()
            .await
            .wrap_err_with(|| format!("failed to read validator balance for {}", validator))?;
        if balance.stakeAmount > U256::ZERO && balance.lastRewardEpoch < current_epoch {
            return Ok(true);
        }
    }

    Ok(false)
}

async fn advance_to_timestamp_if_needed(
    context: &ValidatorContext<'_>,
    target_timestamp: U256,
) -> Result<u64> {
    let current_timestamp = current_block_timestamp(context.base_chain).await?;
    let target_timestamp_u64 = u64::try_from(target_timestamp)
        .map_err(|_| eyre!("target timestamp {} exceeds u64", target_timestamp))?;
    if current_timestamp >= target_timestamp_u64 {
        return Ok(0);
    }

    advance_time_on_chain(&context.base_chain.rpc_url, target_timestamp_u64 - current_timestamp + 1)
        .await
}

async fn current_block_timestamp(chain: &ChainConfig) -> Result<u64> {
    let provider = read_provider(chain).await?;
    let block = provider
        .get_block_by_number(BlockNumberOrTag::Latest)
        .await
        .wrap_err("failed to fetch latest block")?
        .ok_or_else(|| eyre!("latest block not found on chain {}", chain.id))?;
    Ok(block.header.timestamp)
}

async fn impersonated_call(
    chain: &ChainConfig,
    from: Address,
    to: Address,
    data: Vec<u8>,
) -> Result<TransactionReceipt> {
    let rpc_client = HttpClientBuilder::default()
        .build(chain.rpc_url.clone())
        .wrap_err("failed to connect to chain RPC")?;
    let provider = read_provider(chain).await?;

    let _: Value = rpc_client
        .request("anvil_impersonateAccount", rpc_params![from])
        .await
        .wrap_err("failed to impersonate account on Anvil")?;
    let _: Value = rpc_client
        .request(
            "anvil_setBalance",
            rpc_params![from, format!("0x{:x}", U256::from(IMPERSONATED_BALANCE_WEI))],
        )
        .await
        .wrap_err("failed to fund impersonated account on Anvil")?;

    let transaction = json!({
        "from": from.to_string(),
        "to": to.to_string(),
        "data": format!("0x{}", hex::encode(data)),
        "gas": "0x7a1200",
        "value": "0x0",
    });
    let transaction_hash: B256 = rpc_client
        .request("eth_sendTransaction", rpc_params![transaction])
        .await
        .wrap_err("failed to send impersonated transaction")?;

    let receipt = wait_for_receipt(&provider, transaction_hash).await?;
    let _ =
        rpc_client.request::<Value, _>("anvil_stopImpersonatingAccount", rpc_params![from]).await;
    ensure_successful_receipt("impersonated transaction", &receipt)?;
    Ok(receipt)
}

async fn wait_for_receipt(
    provider: &DynProvider,
    transaction_hash: B256,
) -> Result<TransactionReceipt> {
    for _ in 0..40 {
        if let Some(receipt) = provider
            .get_transaction_receipt(transaction_hash)
            .await
            .wrap_err("failed to poll transaction receipt")?
        {
            return Ok(receipt);
        }
        sleep(Duration::from_millis(250)).await;
    }

    bail!("timed out waiting for transaction receipt {}", transaction_hash)
}

async fn advance_time_on_chain(rpc_url: &str, seconds: u64) -> Result<u64> {
    let rpc_client =
        HttpClientBuilder::default().build(rpc_url).wrap_err("failed to connect to chain RPC")?;
    let _: Value = rpc_client
        .request("evm_increaseTime", rpc_params![seconds])
        .await
        .wrap_err("failed to increase Anvil time")?;
    let _: Value = rpc_client
        .request("evm_mine", rpc_params![])
        .await
        .wrap_err("failed to mine block after time increase")?;
    Ok(seconds)
}

fn validator_status_label(status: u8) -> &'static str {
    match status {
        0 => "Inactive",
        1 => "Active",
        2 => "Unstaking",
        3 => "Slashed",
        _ => "Unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::validate_slashable_status;

    #[test]
    fn validate_slashable_status_allows_active_validator() {
        validate_slashable_status("Active", "alice", false).unwrap();
    }

    #[test]
    fn validate_slashable_status_allows_forced_non_active_validator() {
        validate_slashable_status("Inactive", "alice", true).unwrap();
    }

    #[test]
    fn validate_slashable_status_rejects_non_active_validator_without_force() {
        let error = validate_slashable_status("Inactive", "alice", false).unwrap_err();
        assert!(error
            .to_string()
            .contains("refusing to slash a non-active validator without --force"));
    }
}

async fn ensure_contract_code(
    provider: &DynProvider,
    address: Address,
    label: &str,
    runtime: &LoadedRuntime,
    chain: &ChainConfig,
) -> Result<()> {
    let code = provider
        .get_code_at(address)
        .await
        .wrap_err_with(|| format!("failed to fetch code for {label} at {address}"))?;
    if code.is_empty() {
        bail!(
            "{} address {} has no code on chain {} via {}. active config: {}",
            label,
            address,
            chain.id,
            chain.rpc_url,
            runtime.config_path.display()
        );
    }

    Ok(())
}
