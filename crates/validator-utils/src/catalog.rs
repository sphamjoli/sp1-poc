use crate::crypto::{parse_hex_bytes_32, parse_u256_hex, sign_stake_pop};
use alloy::{
    primitives::{Address, U256},
    signers::local::PrivateKeySigner,
};
use eyre::{eyre, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashMap},
    fs,
    path::Path,
};
use sylow::Fp;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DevValidator {
    pub name: String,
    pub wallet_address: String,
    pub evm_private_key: String,
    pub bls_private_key: String,
    pub bls_public_key: [String; 4],
    pub stake_pop_signature_by_chain: BTreeMap<String, [String; 2]>,
    #[serde(default)]
    pub legacy: Option<serde_json::Value>,
}

#[derive(Debug, Clone)]
pub struct ValidatorCatalog {
    validators: Vec<DevValidator>,
    indexes_by_name: HashMap<String, usize>,
    indexes_by_address: HashMap<Address, usize>,
}

impl ValidatorCatalog {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes =
            fs::read(path).wrap_err_with(|| format!("failed to read {}", path.display()))?;
        let validators: Vec<DevValidator> = serde_json::from_slice(&bytes)
            .wrap_err_with(|| format!("invalid validator catalog {}", path.display()))?;

        let mut indexes_by_name = HashMap::with_capacity(validators.len());
        let mut indexes_by_address = HashMap::with_capacity(validators.len());

        for (index, validator) in validators.iter().enumerate() {
            indexes_by_name.insert(validator.name.clone(), index);
            indexes_by_address.insert(validator.address()?, index);
        }

        Ok(Self { validators, indexes_by_name, indexes_by_address })
    }

    pub fn validators(&self) -> &[DevValidator] {
        &self.validators
    }

    pub fn by_name(&self, validator_name: &str) -> Result<&DevValidator> {
        self.indexes_by_name
            .get(validator_name)
            .map(|index| &self.validators[*index])
            .ok_or_else(|| eyre!("unknown validator {validator_name}"))
    }

    pub fn by_address(&self, validator_address: Address) -> Result<&DevValidator> {
        self.indexes_by_address
            .get(&validator_address)
            .map(|index| &self.validators[*index])
            .ok_or_else(|| eyre!("validator {validator_address} is not in the dev catalog"))
    }
}

impl DevValidator {
    pub fn address(&self) -> Result<Address> {
        self.wallet_address
            .parse()
            .wrap_err_with(|| format!("invalid validator address {}", self.wallet_address))
    }

    pub fn evm_signer(&self) -> Result<PrivateKeySigner> {
        self.evm_private_key
            .parse()
            .wrap_err_with(|| format!("invalid EVM private key for {}", self.name))
    }

    pub fn bls_secret_key(&self) -> Result<Fp> {
        let bytes = parse_hex_bytes_32(&self.bls_private_key)?;
        Fp::from_be_bytes(&bytes)
            .into_option()
            .ok_or_else(|| eyre!("invalid BLS private key for {}", self.name))
    }

    pub fn bls_public_key_words(&self) -> Result<[U256; 4]> {
        Ok([
            parse_u256_hex(&self.bls_public_key[0])?,
            parse_u256_hex(&self.bls_public_key[1])?,
            parse_u256_hex(&self.bls_public_key[2])?,
            parse_u256_hex(&self.bls_public_key[3])?,
        ])
    }

    pub fn stake_pop_signature(&self, chain_id: u64) -> Result<[U256; 2]> {
        if let Some(signature_words) = self.stake_pop_signature_by_chain.get(&chain_id.to_string())
        {
            return Ok([
                parse_u256_hex(&signature_words[0])?,
                parse_u256_hex(&signature_words[1])?,
            ]);
        }

        sign_stake_pop(self, chain_id)
    }
}

#[cfg(test)]
mod tests {
    use super::ValidatorCatalog;
    use crate::DEFAULT_RUNTIME_CONFIG;
    use std::path::PathBuf;

    #[test]
    fn validator_catalog_loads_expected_names() {
        let workspace_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let validator_catalog =
            ValidatorCatalog::load(&workspace_root.join("config/dev-validators.json"))
                .expect("validator catalog should load");

        assert_eq!(validator_catalog.validators().len(), 5);
        assert_eq!(validator_catalog.by_name("alice").expect("alice").name, "alice");
        assert_eq!(
            PathBuf::from(DEFAULT_RUNTIME_CONFIG),
            PathBuf::from("config/runtime.local.json")
        );
    }
}
