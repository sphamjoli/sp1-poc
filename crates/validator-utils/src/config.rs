use eyre::{Context, ContextCompat, Result};
use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf};
use url::Url;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RuntimeConfig {
    pub base_chain_id: u64,
    #[serde(default)]
    pub owner_private_key: Option<String>,
    pub runtime: RuntimePaths,
    pub services: RuntimeServices,
    pub indexer: IndexerConfig,
    pub validators_path: PathBuf,
    pub deployments_dir: PathBuf,
    #[serde(default)]
    pub chains_path: Option<PathBuf>,
    #[serde(default)]
    pub chains: Vec<ChainConfig>,
    #[serde(default)]
    pub bootstrap: BootstrapConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RuntimePaths {
    pub state_dir: PathBuf,
    pub log_dir: PathBuf,
    pub pid_dir: PathBuf,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RuntimeServices {
    pub chain_manager: ChainManagerService,
    pub node_manager: NodeManagerService,
    pub validator: ValidatorService,
    pub sp1: Sp1Service,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ChainManagerService {
    pub bind: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct NodeManagerService {
    pub bind: String,
    pub certificate_ttl_secs: u64,
    pub reconcile_interval_secs: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ValidatorService {
    pub poll_interval_secs: u64,
    pub max_backoff_secs: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Sp1Service {
    pub interval_secs: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct IndexerConfig {
    pub hasura_url: String,
    pub hasura_secret: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ChainConfig {
    pub id: u64,
    pub name: String,
    pub rpc_url: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct BootstrapConfig {
    #[serde(default = "default_gas_threshold")]
    pub gas_threshold_wei: String,
    #[serde(default = "default_gas_topup")]
    pub gas_topup_wei: String,
    #[serde(default)]
    pub staking_amount_wei: Option<String>,
}

impl RuntimeConfig {
    pub fn read(path: &PathBuf) -> Result<Self> {
        let bytes =
            fs::read(path).wrap_err_with(|| format!("failed to read {}", path.display()))?;
        let mut runtime_config: Self = serde_json::from_slice(&bytes)
            .wrap_err_with(|| format!("invalid runtime config {}", path.display()))?;
        runtime_config.load_chain_configs(path)?;
        runtime_config.apply_environment_overrides()?;
        Ok(runtime_config)
    }

    fn load_chain_configs(&mut self, config_path: &PathBuf) -> Result<()> {
        if !self.chains.is_empty() {
            return Ok(());
        }

        let Some(chains_path) = &self.chains_path else {
            return Ok(());
        };

        let resolved_chains_path = resolve_configured_path(config_path, chains_path);
        let mut chain_configs = Vec::new();

        for directory_entry in fs::read_dir(&resolved_chains_path)
            .wrap_err_with(|| format!("failed to read {}", resolved_chains_path.display()))?
        {
            let directory_entry = directory_entry?;
            let entry_path = directory_entry.path();
            if !entry_path.is_dir() {
                continue;
            }

            let chain_id =
                directory_entry.file_name().to_string_lossy().parse::<u64>().wrap_err_with(
                    || format!("invalid chain directory {}", entry_path.display()),
                )?;
            let chain_config_path = entry_path.join("chain.json");
            let chain_bytes = fs::read(&chain_config_path)
                .wrap_err_with(|| format!("failed to read {}", chain_config_path.display()))?;
            let chain_config: ChainConfig =
                serde_json::from_slice(&chain_bytes).wrap_err_with(|| {
                    format!("invalid chain config {}", chain_config_path.display())
                })?;

            if chain_config.id != chain_id {
                eyre::bail!(
                    "chain config {} has id {} but directory is {}",
                    chain_config_path.display(),
                    chain_config.id,
                    chain_id
                );
            }

            chain_configs.push(chain_config);
        }

        chain_configs.sort_by_key(|chain_config| chain_config.id);
        self.chains = chain_configs;
        Ok(())
    }

    fn apply_environment_overrides(&mut self) -> Result<()> {
        for chain_config in &mut self.chains {
            let rpc_override_variable = format!("RPC_URL_{}", chain_config.id);
            if let Ok(rpc_url_override) = std::env::var(&rpc_override_variable) {
                if !rpc_url_override.trim().is_empty() {
                    chain_config.rpc_url = rpc_url_override;
                    continue;
                }
            }

            let port_override_variable = format!("ANVIL_PORT_{}", chain_config.id);
            if let Ok(port_override) = std::env::var(&port_override_variable) {
                if !port_override.trim().is_empty() {
                    chain_config.rpc_url = replace_url_port(&chain_config.rpc_url, &port_override)?;
                }
            }
        }

        if let Ok(chain_manager_bind) = std::env::var("CHAIN_MANAGER_BIND") {
            if !chain_manager_bind.trim().is_empty() {
                self.services.chain_manager.bind = chain_manager_bind;
            }
        } else if let Ok(chain_manager_port) = std::env::var("CHAIN_MANAGER_PORT") {
            if !chain_manager_port.trim().is_empty() {
                self.services.chain_manager.bind =
                    replace_bind_port(&self.services.chain_manager.bind, &chain_manager_port)?;
            }
        }

        if let Ok(node_manager_bind) = std::env::var("NODE_MANAGER_BIND") {
            if !node_manager_bind.trim().is_empty() {
                self.services.node_manager.bind = node_manager_bind;
            }
        } else if let Ok(node_manager_port) = std::env::var("NODE_MANAGER_PORT") {
            if !node_manager_port.trim().is_empty() {
                self.services.node_manager.bind =
                    replace_bind_port(&self.services.node_manager.bind, &node_manager_port)?;
            }
        }

        if let Ok(hasura_url) = std::env::var("HASURA_URL") {
            if !hasura_url.trim().is_empty() {
                self.indexer.hasura_url = hasura_url;
            }
        } else if let Ok(hasura_external_port) = std::env::var("HASURA_EXTERNAL_PORT") {
            if !hasura_external_port.trim().is_empty() {
                self.indexer.hasura_url =
                    replace_url_port(&self.indexer.hasura_url, &hasura_external_port)?;
            }
        }

        if let Ok(hasura_secret) = std::env::var("HASURA_SECRET") {
            if !hasura_secret.trim().is_empty() {
                self.indexer.hasura_secret = hasura_secret;
            }
        } else if let Ok(hasura_admin_secret) = std::env::var("HASURA_GRAPHQL_ADMIN_SECRET") {
            if !hasura_admin_secret.trim().is_empty() {
                self.indexer.hasura_secret = hasura_admin_secret;
            }
        }

        if let Ok(poll_interval_seconds) = std::env::var("VALIDATOR_POLL_INTERVAL_SECS") {
            if !poll_interval_seconds.trim().is_empty() {
                self.services.validator.poll_interval_secs = poll_interval_seconds
                    .parse()
                    .wrap_err("invalid VALIDATOR_POLL_INTERVAL_SECS")?;
            }
        }

        if let Ok(max_backoff_seconds) = std::env::var("VALIDATOR_MAX_BACKOFF_SECS") {
            if !max_backoff_seconds.trim().is_empty() {
                self.services.validator.max_backoff_secs =
                    max_backoff_seconds.parse().wrap_err("invalid VALIDATOR_MAX_BACKOFF_SECS")?;
            }
        }

        if let Ok(sp1_interval_seconds) = std::env::var("SP1_INTERVAL_SECS") {
            if !sp1_interval_seconds.trim().is_empty() {
                self.services.sp1.interval_secs =
                    sp1_interval_seconds.parse().wrap_err("invalid SP1_INTERVAL_SECS")?;
            }
        }

        Ok(())
    }
}

impl Default for BootstrapConfig {
    fn default() -> Self {
        Self {
            gas_threshold_wei: default_gas_threshold(),
            gas_topup_wei: default_gas_topup(),
            staking_amount_wei: None,
        }
    }
}

fn default_gas_threshold() -> String {
    "1000000000000000000".to_owned()
}

fn default_gas_topup() -> String {
    "5000000000000000000".to_owned()
}

fn replace_bind_port(bind: &str, port: &str) -> Result<String> {
    let separator_index =
        bind.rfind(':').wrap_err_with(|| format!("invalid bind address {bind}"))?;
    Ok(format!("{}:{}", &bind[..separator_index], port))
}

fn replace_url_port(url: &str, port: &str) -> Result<String> {
    let mut parsed_url = Url::parse(url).wrap_err_with(|| format!("invalid url {url}"))?;
    parsed_url
        .set_port(Some(port.parse().wrap_err_with(|| format!("invalid port {port}"))?))
        .map_err(|_| eyre::eyre!("failed to set port on {url}"))?;
    Ok(parsed_url.to_string())
}

fn resolve_configured_path(config_path: &PathBuf, configured_path: &PathBuf) -> PathBuf {
    if configured_path.is_absolute() {
        return configured_path.clone();
    }

    let current_directory = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let workspace_candidate = current_directory.join(configured_path);
    if workspace_candidate.exists() {
        return workspace_candidate;
    }

    if let Some(workspace_root) = find_workspace_root(config_path.parent()) {
        let workspace_root_candidate = workspace_root.join(configured_path);
        if workspace_root_candidate.exists() {
            return workspace_root_candidate;
        }
    }

    config_path
        .parent()
        .map(|parent_directory| parent_directory.join(configured_path))
        .unwrap_or_else(|| configured_path.clone())
}

fn find_workspace_root(starting_directory: Option<&std::path::Path>) -> Option<PathBuf> {
    starting_directory.and_then(|directory| {
        directory.ancestors().find_map(|candidate| {
            let cargo_manifest_path = candidate.join("Cargo.toml");
            let crates_directory = candidate.join("crates");
            if cargo_manifest_path.exists() && crates_directory.is_dir() {
                Some(candidate.to_path_buf())
            } else {
                None
            }
        })
    })
}
