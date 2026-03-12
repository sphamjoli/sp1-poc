use crate::{
    bindings::{IValidatorManager, ValidatorInfo},
    catalog::DevValidator,
    providers::{read_provider, signer_provider},
    runtime::LoadedRuntime,
    transactions::ensure_successful_receipt,
};
use eyre::{bail, Result, WrapErr};

#[derive(Debug)]
pub struct ValidatorReconciler<'runtime> {
    runtime: &'runtime LoadedRuntime,
}

impl<'runtime> ValidatorReconciler<'runtime> {
    pub fn new(runtime: &'runtime LoadedRuntime) -> Self {
        Self { runtime }
    }

    pub async fn reconcile_on_chain(&self, chain_id: u64, validator: &DevValidator) -> Result<()> {
        let base_chain = self.runtime.base_chain()?;
        let base_deploy = self.runtime.deployment(base_chain.id)?;
        let base_provider = read_provider(base_chain).await?;
        let base_validator_manager =
            IValidatorManager::new(base_deploy.validator_manager, base_provider);
        let base_validator_info = base_validator_manager
            .getValidator(validator.address()?)
            .call()
            .await
            .wrap_err("failed to read base validator during reconcile")?;

        let target_chain = self.runtime.chain(chain_id)?;
        let target_deploy = self.runtime.deployment(chain_id)?;
        let owner_provider = signer_provider(target_chain, self.runtime.owner_signer()?).await?;
        let target_validator_manager =
            IValidatorManager::new(target_deploy.validator_manager, owner_provider.clone());
        let current_target_validator_info = target_validator_manager
            .getValidator(validator.address()?)
            .call()
            .await
            .wrap_err("failed to read target validator during reconcile")?;

        if current_target_validator_info.wallet == alloy::primitives::Address::ZERO {
            let validator_info = ValidatorInfo {
                blsPublicKey: validator.bls_public_key_words()?,
                status: base_validator_info.status,
                attestationCount: alloy::primitives::U256::ZERO,
                invalidAttestations: alloy::primitives::U256::ZERO,
                wallet: validator.address()?,
            };
            let receipt = target_validator_manager
                .addValidator(validator_info)
                .send()
                .await
                .wrap_err("failed to add validator during reconcile")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for addValidator receipt during reconcile")?;
            ensure_successful_receipt(
                &format!("reconcile addValidator for {} on chain {}", validator.name, chain_id),
                &receipt,
            )?;
        }

        let refreshed_target_validator_info = target_validator_manager
            .getValidator(validator.address()?)
            .call()
            .await
            .wrap_err("failed to refresh target validator during reconcile")?;

        if refreshed_target_validator_info.blsPublicKey != validator.bls_public_key_words()? {
            bail!(
                "validator {} on chain {} has an unexpected BLS key; manual reset is required",
                validator.name,
                chain_id
            );
        }

        if refreshed_target_validator_info.status != base_validator_info.status {
            let receipt = target_validator_manager
                .updateValidatorStatus(validator.address()?, base_validator_info.status)
                .send()
                .await
                .wrap_err("failed to update validator status during reconcile")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for updateValidatorStatus receipt during reconcile")?;
            ensure_successful_receipt(
                &format!(
                    "reconcile updateValidatorStatus for {} on chain {}",
                    validator.name, chain_id
                ),
                &receipt,
            )?;
        }

        Ok(())
    }
}
