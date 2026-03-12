use crate::{
    catalog::ValidatorCatalog,
    config::{ChainConfig, RuntimeConfig},
};
use alloy::{primitives::Address, signers::local::PrivateKeySigner};
use eyre::{eyre, Result, WrapErr};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DeployAddresses {
    pub bridge: Address,
    #[serde(rename = "stakeManager")]
    pub stake_manager: Address,
    #[serde(rename = "tokenA")]
    pub token_a: Address,
    #[serde(rename = "tokenB")]
    pub token_b: Address,
    #[serde(rename = "validatorManager")]
    pub validator_manager: Address,
}

#[derive(Debug, Clone)]
pub struct LoadedRuntime {
    pub config_path: PathBuf,
    pub workspace_root: PathBuf,
    pub config: RuntimeConfig,
    pub owner_private_key: String,
    pub validator_catalog: ValidatorCatalog,
    pub deployments: BTreeMap<u64, DeployAddresses>,
}

impl LoadedRuntime {
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let provided_config_path = path.as_ref();
        let current_directory = std::env::current_dir().wrap_err("failed to resolve cwd")?;
        let config_path = if provided_config_path.is_absolute() {
            provided_config_path.to_path_buf()
        } else {
            current_directory.join(provided_config_path)
        };
        let config = RuntimeConfig::read(&config_path)?;
        let workspace_root = derive_workspace_root(&current_directory, &config_path);
        let owner_private_key = resolve_owner_private_key(&config)?;

        let validators_path =
            resolve_runtime_path(&workspace_root, &config_path, &config.validators_path);
        let validator_catalog = ValidatorCatalog::load(&validators_path)?;

        let deployments_directory =
            resolve_runtime_path(&workspace_root, &config_path, &config.deployments_dir);
        let mut deployments = BTreeMap::new();

        for chain_config in &config.chains {
            let deployment_path = deployments_directory.join(format!("{}.json", chain_config.id));
            if deployment_path.exists() {
                let bytes = fs::read(&deployment_path)
                    .wrap_err_with(|| format!("failed to read {}", deployment_path.display()))?;
                let deploy_addresses: DeployAddresses = serde_json::from_slice(&bytes)
                    .wrap_err_with(|| {
                        format!("invalid deployment artifact {}", deployment_path.display())
                    })?;
                deployments.insert(chain_config.id, deploy_addresses);
            }
        }

        Ok(Self {
            config_path,
            workspace_root,
            config,
            owner_private_key,
            validator_catalog,
            deployments,
        })
    }

    pub fn chain(&self, chain_id: u64) -> Result<&ChainConfig> {
        self.config
            .chains
            .iter()
            .find(|chain_config| chain_config.id == chain_id)
            .ok_or_else(|| eyre!("chain {chain_id} is not configured"))
    }

    pub fn base_chain(&self) -> Result<&ChainConfig> {
        self.chain(self.config.base_chain_id)
    }

    pub fn deployment(&self, chain_id: u64) -> Result<&DeployAddresses> {
        self.deployments
            .get(&chain_id)
            .ok_or_else(|| eyre!("missing deployment artifact for chain {chain_id}"))
    }

    pub fn owner_signer(&self) -> Result<PrivateKeySigner> {
        self.owner_private_key.parse().wrap_err("failed to parse owner private key")
    }

    pub fn owner_address(&self) -> Result<Address> {
        Ok(self.owner_signer()?.address())
    }

    pub fn state_path(&self, relative_path: impl AsRef<Path>) -> PathBuf {
        self.workspace_root.join(&self.config.runtime.state_dir).join(relative_path)
    }

    pub fn log_path(&self, relative_path: impl AsRef<Path>) -> PathBuf {
        self.workspace_root.join(&self.config.runtime.log_dir).join(relative_path)
    }

    pub fn pid_path(&self, relative_path: impl AsRef<Path>) -> PathBuf {
        self.workspace_root.join(&self.config.runtime.pid_dir).join(relative_path)
    }

    pub fn ensure_runtime_directories(&self) -> Result<()> {
        for directory in [
            self.workspace_root.join(&self.config.runtime.state_dir),
            self.workspace_root.join(&self.config.runtime.log_dir),
            self.workspace_root.join(&self.config.runtime.pid_dir),
        ] {
            fs::create_dir_all(&directory)
                .wrap_err_with(|| format!("failed to create {}", directory.display()))?;
        }
        Ok(())
    }
}

fn resolve_owner_private_key(config: &RuntimeConfig) -> Result<String> {
    read_non_empty_environment_variable("NODE_MANAGER_PRIVATE_KEY")
        .or_else(|| read_non_empty_environment_variable("OWNER_PRIVATE_KEY"))
        .or_else(|| read_non_empty_environment_variable("NETWORK_PRIVATE_KEY"))
        .or_else(|| config.owner_private_key.clone())
        .ok_or_else(|| eyre!(
            "missing owner private key; set NODE_MANAGER_PRIVATE_KEY, OWNER_PRIVATE_KEY, NETWORK_PRIVATE_KEY, or owner_private_key in runtime config"
        ))
}

fn read_non_empty_environment_variable(name: &str) -> Option<String> {
    std::env::var(name).ok().and_then(|value| {
        let trimmed_value = value.trim();
        if trimmed_value.is_empty() {
            None
        } else {
            Some(trimmed_value.to_owned())
        }
    })
}

fn derive_workspace_root(current_directory: &Path, config_path: &Path) -> PathBuf {
    let config_directory = config_path.parent().unwrap_or(current_directory);

    find_workspace_root(config_directory)
        .or_else(|| find_workspace_root(current_directory))
        .unwrap_or_else(|| current_directory.to_path_buf())
}

fn find_workspace_root(starting_directory: &Path) -> Option<PathBuf> {
    starting_directory.ancestors().find_map(|candidate| {
        let cargo_manifest_path = candidate.join("Cargo.toml");
        let crates_directory = candidate.join("crates");
        if cargo_manifest_path.exists() && crates_directory.is_dir() {
            Some(candidate.to_path_buf())
        } else {
            None
        }
    })
}

fn resolve_runtime_path(
    workspace_root: &Path,
    config_path: &Path,
    configured_path: &Path,
) -> PathBuf {
    if configured_path.is_absolute() {
        return configured_path.to_path_buf();
    }

    let workspace_candidate = workspace_root.join(configured_path);
    if workspace_candidate.exists() {
        return workspace_candidate;
    }

    let config_directory = config_path.parent().unwrap_or(workspace_root);
    let config_directory_candidate = config_directory.join(configured_path);
    if config_directory_candidate.exists() {
        return config_directory_candidate;
    }

    workspace_candidate
}
