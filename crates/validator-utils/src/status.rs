use crate::{
    bindings::{IStakeManager, IValidatorManager, ValidatorBalance, IERC20},
    providers::read_provider,
    runtime::LoadedRuntime,
};
use alloy::primitives::U256;
use eyre::{Result, WrapErr};
use serde::Serialize;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValidatorStatus {
    Inactive,
    Active,
    Unstaking,
    Slashed,
    Unknown(u8),
}

impl From<u8> for ValidatorStatus {
    fn from(value: u8) -> Self {
        match value {
            crate::bindings::STATUS_INACTIVE => Self::Inactive,
            crate::bindings::STATUS_ACTIVE => Self::Active,
            crate::bindings::STATUS_UNSTAKING => Self::Unstaking,
            crate::bindings::STATUS_SLASHED => Self::Slashed,
            other => Self::Unknown(other),
        }
    }
}

impl fmt::Display for ValidatorStatus {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Inactive => formatter.write_str("Inactive"),
            Self::Active => formatter.write_str("Active"),
            Self::Unstaking => formatter.write_str("Unstaking"),
            Self::Slashed => formatter.write_str("Slashed"),
            Self::Unknown(value) => write!(formatter, "Unknown({value})"),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ValidatorChainSync {
    pub chain_id: u64,
    pub status: String,
    pub expected_status: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ValidatorStatusReport {
    pub name: String,
    pub wallet: alloy::primitives::Address,
    #[serde(rename = "baseStatus")]
    pub base_status: String,
    #[serde(rename = "baseStakeAmount")]
    pub base_stake_amount: String,
    #[serde(rename = "pendingRewards")]
    pub pending_rewards: String,
    #[serde(rename = "lastRewardEpoch")]
    pub last_reward_epoch: String,
    #[serde(rename = "attestationCount")]
    pub attestation_count: String,
    #[serde(rename = "invalidAttestations")]
    pub invalid_attestations: String,
    pub synced: Vec<ValidatorChainSync>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RuntimeStatusReport {
    pub owner: alloy::primitives::Address,
    #[serde(rename = "baseChainId")]
    pub base_chain_id: u64,
    #[serde(rename = "baseStakeManager")]
    pub base_stake_manager: alloy::primitives::Address,
    #[serde(rename = "currentEpoch")]
    pub current_epoch: String,
    #[serde(rename = "epochDurationSeconds")]
    pub epoch_duration_seconds: String,
    #[serde(rename = "epochsPerYear")]
    pub epochs_per_year: String,
    #[serde(rename = "activeValidatorCount")]
    pub active_validator_count: usize,
    #[serde(rename = "totalBaseStakeAmount")]
    pub total_base_stake_amount: String,
    #[serde(rename = "totalPendingRewards")]
    pub total_pending_rewards: String,
    #[serde(rename = "rewardTokenAddress")]
    pub reward_token_address: alloy::primitives::Address,
    #[serde(rename = "rewardTokenSymbol")]
    pub reward_token_symbol: String,
    #[serde(rename = "rewardTokenDecimals")]
    pub reward_token_decimals: u8,
    #[serde(rename = "rewardReserveBalance")]
    pub reward_reserve_balance: String,
    #[serde(rename = "ownerRewardTokenBalance")]
    pub owner_reward_token_balance: String,
    #[serde(rename = "bridgeWiring")]
    pub bridge_wiring: Vec<String>,
    #[serde(rename = "managerOwners")]
    pub manager_owners: Vec<String>,
    pub validators: Vec<ValidatorStatusReport>,
}

#[derive(Debug)]
pub struct RuntimeStatusReporter<'runtime> {
    runtime: &'runtime LoadedRuntime,
}

impl<'runtime> RuntimeStatusReporter<'runtime> {
    pub fn new(runtime: &'runtime LoadedRuntime) -> Self {
        Self { runtime }
    }

    pub async fn generate(&self) -> Result<RuntimeStatusReport> {
        let owner_address = self.runtime.owner_address()?;
        let mut bridge_wiring = Vec::new();
        let mut manager_owners = Vec::new();

        for chain_config in &self.runtime.config.chains {
            let deploy_addresses = self.runtime.deployment(chain_config.id)?;
            let provider = read_provider(chain_config).await?;
            let bridge_contract =
                crate::bindings::IBridge::new(deploy_addresses.bridge, provider.clone());
            let validator_manager_contract =
                IValidatorManager::new(deploy_addresses.validator_manager, provider.clone());

            let current_bridge_target =
                bridge_contract.VALIDATOR_MANAGER().call().await.wrap_err_with(|| {
                    format!("failed to read bridge wiring on chain {}", chain_config.id)
                })?;
            bridge_wiring.push(format!(
                "chain {} bridge validator manager {}{}",
                chain_config.id,
                current_bridge_target,
                if current_bridge_target == deploy_addresses.validator_manager {
                    ""
                } else {
                    " (mismatch)"
                }
            ));

            let current_manager_owner =
                validator_manager_contract.owner().call().await.wrap_err_with(|| {
                    format!("failed to read validator manager owner on chain {}", chain_config.id)
                })?;
            manager_owners.push(format!(
                "chain {} validator manager owner {}{}",
                chain_config.id,
                current_manager_owner,
                if current_manager_owner == owner_address { "" } else { " (mismatch)" }
            ));
        }

        let base_chain = self.runtime.base_chain()?;
        let base_deploy = self.runtime.deployment(base_chain.id)?;
        let base_provider = read_provider(base_chain).await?;
        let base_validator_manager =
            IValidatorManager::new(base_deploy.validator_manager, base_provider.clone());
        let base_stake_manager =
            IStakeManager::new(base_deploy.stake_manager, base_provider.clone());
        let active_staking_config = base_stake_manager
            .ACTIVE_STAKING_CONFIG()
            .call()
            .await
            .wrap_err("failed to read active staking config")?;
        let reward_token = IERC20::new(active_staking_config.stakingToken, base_provider.clone());
        let current_epoch =
            base_validator_manager.EPOCH().call().await.wrap_err("failed to read current epoch")?;
        let epoch_duration_seconds = base_validator_manager
            .epochDuration()
            .call()
            .await
            .wrap_err("failed to read epoch duration")?;
        let epochs_per_year = base_validator_manager
            .getEpochsPerYear()
            .call()
            .await
            .wrap_err("failed to read epochs per year")?;
        let active_validator_count = base_validator_manager
            .getActiveValidators()
            .call()
            .await
            .wrap_err("failed to read active validators")?
            .len();
        let mut validators = Vec::with_capacity(self.runtime.validator_catalog.validators().len());
        let mut total_base_stake_amount = U256::ZERO;
        let mut total_pending_rewards = U256::ZERO;

        for validator in self.runtime.validator_catalog.validators() {
            let base_validator_info = base_validator_manager
                .getValidator(validator.address()?)
                .call()
                .await
                .wrap_err("failed to read base validator status")?;
            let base_validator_balance: ValidatorBalance = base_stake_manager
                .validatorBalance(validator.address()?)
                .call()
                .await
                .wrap_err("failed to read base validator balance")?;
            let expected_status = ValidatorStatus::from(base_validator_info.status);
            total_base_stake_amount += base_validator_balance.stakeAmount;
            total_pending_rewards += base_validator_balance.balance;
            let mut synced = Vec::with_capacity(self.runtime.config.chains.len());

            for chain_config in &self.runtime.config.chains {
                let deploy_addresses = self.runtime.deployment(chain_config.id)?;
                let provider = read_provider(chain_config).await?;
                let validator_manager =
                    IValidatorManager::new(deploy_addresses.validator_manager, provider);
                let validator_info = validator_manager
                    .getValidator(validator.address()?)
                    .call()
                    .await
                    .wrap_err_with(|| {
                        format!(
                            "failed to read validator {} on chain {}",
                            validator.name, chain_config.id
                        )
                    })?;
                synced.push(ValidatorChainSync {
                    chain_id: chain_config.id,
                    status: ValidatorStatus::from(validator_info.status).to_string(),
                    expected_status: expected_status.to_string(),
                });
            }

            validators.push(ValidatorStatusReport {
                name: validator.name.clone(),
                wallet: validator.address()?,
                base_status: expected_status.to_string(),
                base_stake_amount: base_validator_balance.stakeAmount.to_string(),
                pending_rewards: base_validator_balance.balance.to_string(),
                last_reward_epoch: base_validator_balance.lastRewardEpoch.to_string(),
                attestation_count: base_validator_info.attestationCount.to_string(),
                invalid_attestations: base_validator_info.invalidAttestations.to_string(),
                synced,
            });
        }

        let reward_token_symbol =
            reward_token.symbol().call().await.wrap_err("failed to read reward token symbol")?;
        let reward_token_decimals = reward_token
            .decimals()
            .call()
            .await
            .wrap_err("failed to read reward token decimals")?;
        let stake_manager_reward_token_balance = reward_token
            .balanceOf(base_deploy.stake_manager)
            .call()
            .await
            .wrap_err("failed to read stake manager reward token balance")?;
        let owner_reward_token_balance = reward_token
            .balanceOf(owner_address)
            .call()
            .await
            .wrap_err("failed to read owner reward token balance")?;
        let reward_reserve_balance = if stake_manager_reward_token_balance > total_base_stake_amount
        {
            stake_manager_reward_token_balance - total_base_stake_amount
        } else {
            U256::ZERO
        };

        Ok(RuntimeStatusReport {
            owner: owner_address,
            base_chain_id: self.runtime.config.base_chain_id,
            base_stake_manager: base_deploy.stake_manager,
            current_epoch: current_epoch.to_string(),
            epoch_duration_seconds: epoch_duration_seconds.to_string(),
            epochs_per_year: epochs_per_year.to_string(),
            active_validator_count,
            total_base_stake_amount: total_base_stake_amount.to_string(),
            total_pending_rewards: total_pending_rewards.to_string(),
            reward_token_address: active_staking_config.stakingToken,
            reward_token_symbol,
            reward_token_decimals,
            reward_reserve_balance: reward_reserve_balance.to_string(),
            owner_reward_token_balance: owner_reward_token_balance.to_string(),
            bridge_wiring,
            manager_owners,
            validators,
        })
    }
}
