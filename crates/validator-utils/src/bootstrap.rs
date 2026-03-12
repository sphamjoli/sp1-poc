use crate::{
    bindings::{
        BlsOwnerShip, IBridge, IStakeManager, IValidatorManager, StakeParams, ValidatorInfo,
        IERC20, STATUS_ACTIVE, STATUS_INACTIVE,
    },
    catalog::DevValidator,
    crypto::parse_u256_hex_or_decimal,
    providers::{read_provider, signer_provider},
    runtime::{DeployAddresses, LoadedRuntime},
    transactions::ensure_successful_receipt,
};
use alloy::{
    network::TransactionBuilder,
    primitives::{Address, U256},
    providers::Provider,
};
use eyre::{bail, Result, WrapErr};

#[derive(Debug)]
pub struct Bootstrapper<'runtime> {
    runtime: &'runtime LoadedRuntime,
}

impl<'runtime> Bootstrapper<'runtime> {
    pub fn new(runtime: &'runtime LoadedRuntime) -> Self {
        Self { runtime }
    }

    pub async fn run(&self) -> Result<()> {
        self.runtime.ensure_runtime_directories()?;
        self.ensure_contract_wiring().await?;
        self.bootstrap_base_validators().await?;
        Ok(())
    }

    async fn ensure_contract_wiring(&self) -> Result<()> {
        let owner_signer = self.runtime.owner_signer()?;
        for chain_config in &self.runtime.config.chains {
            let deploy_addresses = self.runtime.deployment(chain_config.id)?;
            let owner_provider = signer_provider(chain_config, owner_signer.clone()).await?;
            self.ensure_bridge_wiring(&owner_provider, deploy_addresses).await?;
            if chain_config.id == self.runtime.config.base_chain_id {
                self.ensure_base_manager_wiring(&owner_provider, deploy_addresses).await?;
            }
        }
        Ok(())
    }

    async fn bootstrap_base_validators(&self) -> Result<()> {
        let base_chain = self.runtime.base_chain()?;
        let base_deploy = self.runtime.deployment(base_chain.id)?;
        let base_read_provider = read_provider(base_chain).await?;

        let base_stake_manager = IStakeManager::new(
            base_deploy.stake_manager,
            signer_provider(base_chain, self.runtime.owner_signer()?).await?,
        );
        let active_staking_config = base_stake_manager
            .ACTIVE_STAKING_CONFIG()
            .call()
            .await
            .wrap_err("failed to read active staking config")?;
        let stake_version = base_stake_manager
            .getStakeVersion(active_staking_config.clone())
            .call()
            .await
            .wrap_err("failed to compute stake version")?;
        let minimum_stake = active_staking_config.minStakeAmount;
        let target_stake = match &self.runtime.config.bootstrap.staking_amount_wei {
            Some(configured_amount) => parse_u256_hex_or_decimal(configured_amount)?,
            None => minimum_stake,
        };

        for validator in self.runtime.validator_catalog.validators() {
            self.ensure_validator_gas(validator).await?;
            let base_owner_provider =
                signer_provider(base_chain, self.runtime.owner_signer()?).await?;
            self.ensure_validator_registered_on_base(&base_owner_provider, base_deploy, validator)
                .await?;
            let base_owner_provider =
                signer_provider(base_chain, self.runtime.owner_signer()?).await?;
            self.ensure_validator_token_balance(
                &base_owner_provider,
                base_deploy.token_a,
                validator.address()?,
                target_stake,
            )
            .await?;
            self.ensure_validator_staked(
                &base_read_provider,
                base_deploy,
                validator,
                base_chain.id,
                target_stake,
                stake_version,
            )
            .await?;
        }

        Ok(())
    }

    async fn ensure_bridge_wiring(
        &self,
        owner_provider: &alloy::providers::DynProvider,
        deploy_addresses: &DeployAddresses,
    ) -> Result<()> {
        let bridge_contract = IBridge::new(deploy_addresses.bridge, owner_provider.clone());
        let current_validator_manager = bridge_contract
            .VALIDATOR_MANAGER()
            .call()
            .await
            .wrap_err("failed to read bridge VALIDATOR_MANAGER")?;
        if current_validator_manager != deploy_addresses.validator_manager {
            let receipt = bridge_contract
                .updateValidatorManager(deploy_addresses.validator_manager)
                .send()
                .await
                .wrap_err("failed to update bridge validator manager")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for bridge wiring receipt")?;
            ensure_successful_receipt("bridge wiring update", &receipt)?;
        }
        Ok(())
    }

    async fn ensure_base_manager_wiring(
        &self,
        owner_provider: &alloy::providers::DynProvider,
        deploy_addresses: &DeployAddresses,
    ) -> Result<()> {
        let stake_manager =
            IStakeManager::new(deploy_addresses.stake_manager, owner_provider.clone());
        let validator_manager =
            IValidatorManager::new(deploy_addresses.validator_manager, owner_provider.clone());

        let current_stake_target = stake_manager
            .VALIDATOR_MANAGER()
            .call()
            .await
            .wrap_err("failed to read stake manager validator target")?;
        if current_stake_target != deploy_addresses.validator_manager {
            let receipt = stake_manager
                .updateValidatorManager(deploy_addresses.validator_manager)
                .send()
                .await
                .wrap_err("failed to wire stake manager to validator manager")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for stake wiring receipt")?;
            ensure_successful_receipt("stake manager wiring update", &receipt)?;
        }

        let current_validator_target = validator_manager
            .STAKING_MANAGER()
            .call()
            .await
            .wrap_err("failed to read validator manager staking target")?;
        if current_validator_target != deploy_addresses.stake_manager {
            let receipt = validator_manager
                .updateStakingManager(deploy_addresses.stake_manager)
                .send()
                .await
                .wrap_err("failed to wire validator manager to stake manager")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for validator wiring receipt")?;
            ensure_successful_receipt("validator manager wiring update", &receipt)?;
        }

        Ok(())
    }

    async fn ensure_validator_gas(&self, validator: &DevValidator) -> Result<()> {
        let threshold =
            parse_u256_hex_or_decimal(&self.runtime.config.bootstrap.gas_threshold_wei)?;
        let top_up_amount =
            parse_u256_hex_or_decimal(&self.runtime.config.bootstrap.gas_topup_wei)?;
        let owner_signer = self.runtime.owner_signer()?;

        for chain_config in &self.runtime.config.chains {
            let owner_provider = signer_provider(chain_config, owner_signer.clone()).await?;
            let current_balance =
                owner_provider.get_balance(validator.address()?).await.wrap_err_with(|| {
                    format!(
                        "failed to read native balance for {} on chain {}",
                        validator.name, chain_config.id
                    )
                })?;

            if current_balance < threshold {
                let gas_price = owner_provider.get_gas_price().await.wrap_err_with(|| {
                    format!(
                        "failed to quote gas price for {} on chain {}",
                        validator.name, chain_config.id
                    )
                })?;
                let transaction_request = alloy::rpc::types::TransactionRequest::default()
                    .with_to(validator.address()?)
                    .with_value(top_up_amount)
                    .with_gas_price(gas_price);
                let receipt = owner_provider
                    .send_transaction(transaction_request)
                    .await
                    .wrap_err_with(|| {
                        format!(
                            "failed to top up gas for {} on chain {}",
                            validator.name, chain_config.id
                        )
                    })?
                    .get_receipt()
                    .await
                    .wrap_err("failed waiting for gas top-up receipt")?;
                ensure_successful_receipt(
                    &format!("gas top-up for {} on chain {}", validator.name, chain_config.id),
                    &receipt,
                )?;
            }
        }
        Ok(())
    }

    async fn ensure_validator_registered_on_base(
        &self,
        base_owner_provider: &alloy::providers::DynProvider,
        deploy_addresses: &DeployAddresses,
        validator: &DevValidator,
    ) -> Result<()> {
        let validator_manager =
            IValidatorManager::new(deploy_addresses.validator_manager, base_owner_provider.clone());
        let current_validator_info = validator_manager
            .getValidator(validator.address()?)
            .call()
            .await
            .wrap_err("failed to read base validator")?;

        if current_validator_info.wallet == Address::ZERO {
            let validator_info = ValidatorInfo {
                blsPublicKey: validator.bls_public_key_words()?,
                status: STATUS_INACTIVE,
                attestationCount: U256::ZERO,
                invalidAttestations: U256::ZERO,
                wallet: validator.address()?,
            };
            let receipt = validator_manager
                .addValidator(validator_info)
                .send()
                .await
                .wrap_err_with(|| format!("failed to add base validator {}", validator.name))?
                .get_receipt()
                .await
                .wrap_err("failed waiting for addValidator receipt")?;
            ensure_successful_receipt(
                &format!("adding base validator {}", validator.name),
                &receipt,
            )?;
        }

        let refreshed_validator_info = validator_manager
            .getValidator(validator.address()?)
            .call()
            .await
            .wrap_err("failed to refresh base validator")?;
        if refreshed_validator_info.blsPublicKey != validator.bls_public_key_words()? {
            bail!("base validator {} has an unexpected BLS key", validator.name);
        }
        Ok(())
    }

    async fn ensure_validator_token_balance(
        &self,
        base_owner_provider: &alloy::providers::DynProvider,
        token_address: Address,
        validator_address: Address,
        required_balance: U256,
    ) -> Result<()> {
        let staking_token = IERC20::new(token_address, base_owner_provider.clone());
        let current_balance = staking_token
            .balanceOf(validator_address)
            .call()
            .await
            .wrap_err("failed to read validator staking token balance")?;
        if current_balance < required_balance {
            let deficit = required_balance - current_balance;
            let receipt = staking_token
                .transfer(validator_address, deficit)
                .send()
                .await
                .wrap_err("failed to fund validator staking balance")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for validator token funding receipt")?;
            ensure_successful_receipt("validator token funding", &receipt)?;
        }
        Ok(())
    }

    async fn ensure_validator_staked(
        &self,
        base_read_provider: &alloy::providers::DynProvider,
        deploy_addresses: &DeployAddresses,
        validator: &DevValidator,
        chain_id: u64,
        target_stake: U256,
        stake_version: alloy::primitives::FixedBytes<32>,
    ) -> Result<()> {
        let read_only_stake_manager =
            IStakeManager::new(deploy_addresses.stake_manager, base_read_provider.clone());
        let current_balance = read_only_stake_manager
            .validatorBalance(validator.address()?)
            .call()
            .await
            .wrap_err("failed to read validator stake balance")?;

        if current_balance.stakeAmount >= target_stake {
            let current_validator_info = IValidatorManager::new(
                deploy_addresses.validator_manager,
                base_read_provider.clone(),
            )
            .getValidator(validator.address()?)
            .call()
            .await
            .wrap_err("failed to read validator status after existing stake")?;
            if current_validator_info.status == STATUS_ACTIVE {
                return Ok(());
            }
        }

        let validator_provider =
            signer_provider(self.runtime.base_chain()?, validator.evm_signer()?).await?;
        let validator_staking_token =
            IERC20::new(deploy_addresses.token_a, validator_provider.clone());
        let receipt = validator_staking_token
            .approve(deploy_addresses.stake_manager, target_stake)
            .send()
            .await
            .wrap_err_with(|| format!("failed approve() for {}", validator.name))?
            .get_receipt()
            .await
            .wrap_err("failed waiting for approve receipt")?;
        ensure_successful_receipt(&format!("approve() for {}", validator.name), &receipt)?;

        let additional_stake_amount = if current_balance.stakeAmount >= target_stake {
            U256::ZERO
        } else {
            target_stake - current_balance.stakeAmount
        };

        if additional_stake_amount > U256::ZERO {
            let validator_stake_manager =
                IStakeManager::new(deploy_addresses.stake_manager, validator_provider);
            let stake_params =
                StakeParams { stakeAmount: additional_stake_amount, stakeVersion: stake_version };
            let bls_ownership = BlsOwnerShip {
                signature: validator.stake_pop_signature(chain_id)?,
                pubkey: validator.bls_public_key_words()?,
            };
            let receipt = validator_stake_manager
                .stake(stake_params, bls_ownership)
                .send()
                .await
                .wrap_err_with(|| format!("failed stake() for {}", validator.name))?
                .get_receipt()
                .await
                .wrap_err("failed waiting for stake receipt")?;
            ensure_successful_receipt(&format!("stake() for {}", validator.name), &receipt)?;
        }

        let refreshed_validator_info =
            IValidatorManager::new(deploy_addresses.validator_manager, base_read_provider.clone())
                .getValidator(validator.address()?)
                .call()
                .await
                .wrap_err("failed to verify validator status after staking")?;
        if refreshed_validator_info.status != STATUS_ACTIVE {
            bail!("validator {} is not active after bootstrap", validator.name);
        }
        Ok(())
    }
}
