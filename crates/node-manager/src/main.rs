use alloy::primitives::U256;
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use clap::Parser;
use eyre::{bail, Result, WrapErr};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::{collections::BTreeMap, fs, net::SocketAddr, sync::Arc};
use tokio::{
    net::TcpListener,
    sync::RwLock,
    time::{sleep, Duration},
};
use tower_http::cors::CorsLayer;
use tracing::{error, info};
use validator_utils::{
    bindings::{IStakeManager, IValidatorManager, IERC20},
    issue_certificate, parse_u256_hex_or_decimal,
    providers::{read_provider, signer_provider},
    runtime::LoadedRuntime,
    state::write_state_file,
    status::{RuntimeStatusReport, RuntimeStatusReporter, ValidatorStatus, ValidatorStatusReport},
    transactions::ensure_successful_receipt,
    unix_timestamp, CertificateEnvelope, DevValidator, ValidatorReconciler, DEFAULT_RUNTIME_CONFIG,
};

#[derive(Debug, Parser)]
#[command(name = "node-manager")]
#[command(about = "Local validator node manager")]
struct CommandLineInterface {
    #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG, env = "RUNTIME_CONFIG")]
    config: String,
}

#[derive(Debug)]
struct NodeManagerApplication {
    runtime: LoadedRuntime,
    last_reconcile_at: RwLock<Option<u64>>,
    certificate_history: RwLock<Vec<CertificateRecord>>,
}

#[derive(Debug, Clone)]
struct ApplicationState {
    application: Arc<NodeManagerApplication>,
}

#[derive(Debug, Deserialize)]
struct CertificateRequest {
    validator: alloy::primitives::Address,
    #[serde(rename = "targetChainId")]
    target_chain_id: u64,
}

#[derive(Debug, Deserialize)]
struct RewardTopUpRequest {
    #[serde(rename = "amountWei")]
    amount_wei: String,
}

#[derive(Debug, Serialize)]
struct RewardTopUpResponse {
    status: &'static str,
    #[serde(rename = "chainId")]
    chain_id: u64,
    #[serde(rename = "stakeManager")]
    stake_manager: alloy::primitives::Address,
    #[serde(rename = "rewardToken")]
    reward_token: alloy::primitives::Address,
    #[serde(rename = "amountWei")]
    amount_wei: String,
    #[serde(rename = "approveTransactionHash")]
    approve_transaction_hash: String,
    #[serde(rename = "topUpTransactionHash")]
    top_up_transaction_hash: String,
}

#[derive(Debug, Serialize)]
struct RewardDistributionResponse {
    status: &'static str,
    #[serde(rename = "chainId")]
    chain_id: u64,
    epoch: String,
    distributed: bool,
    message: String,
    #[serde(rename = "transactionHash")]
    transaction_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CertificateRecord {
    validator: alloy::primitives::Address,
    #[serde(rename = "targetChainId")]
    target_chain_id: u64,
    #[serde(rename = "issuedAt")]
    issued_at: u64,
    #[serde(rename = "expiresAt")]
    expires_at: u64,
    #[serde(rename = "certificateHex")]
    certificate_hex: String,
    signer: alloy::primitives::Address,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    owner: alloy::primitives::Address,
    #[serde(rename = "validatorCount")]
    validator_count: usize,
    #[serde(rename = "lastReconcileAt")]
    last_reconcile_at: Option<u64>,
    #[serde(rename = "certificateCount")]
    certificate_count: usize,
}

#[derive(Debug, Serialize)]
struct ValidatorsResponse {
    #[serde(rename = "lastReconcileAt")]
    last_reconcile_at: Option<u64>,
    validators: Vec<ValidatorStatusReport>,
}

#[derive(Debug, Serialize, Deserialize)]
struct HeartbeatState {
    status: &'static str,
    owner: alloy::primitives::Address,
    #[serde(rename = "validatorCount")]
    validator_count: usize,
    #[serde(rename = "lastReconcileAt")]
    last_reconcile_at: Option<u64>,
    #[serde(rename = "certificateCount")]
    certificate_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ChainManagerHeartbeat {
    status: String,
    bind: String,
    #[serde(rename = "chainIds")]
    chain_ids: Vec<u64>,
    #[serde(rename = "startedAt")]
    started_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Sp1Heartbeat {
    status: String,
    #[serde(rename = "startedAt")]
    started_at: u64,
    #[serde(rename = "lastRunAt")]
    last_run_at: Option<u64>,
    #[serde(rename = "lastFinalizedSourceChainId")]
    last_finalized_source_chain_id: Option<u64>,
    #[serde(rename = "lastFinalizedBlockNumber")]
    last_finalized_block_number: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ValidatorProcessEntry {
    status: String,
    #[serde(rename = "retryCount")]
    retry_count: u32,
    #[serde(rename = "nextRetryAt")]
    next_retry_at: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
    #[serde(rename = "submittedAt")]
    submitted_at: Option<u64>,
    #[serde(rename = "transactionHash")]
    transaction_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ValidatorProcessState {
    validator: String,
    #[serde(rename = "lastHeartbeatAt")]
    last_heartbeat_at: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
    entries: BTreeMap<String, ValidatorProcessEntry>,
}

#[derive(Debug, Clone, Serialize)]
struct ValidatorProcessSummary {
    validator: String,
    #[serde(rename = "lastHeartbeatAt")]
    last_heartbeat_at: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
    #[serde(rename = "submittedCount")]
    submitted_count: usize,
    #[serde(rename = "pendingCount")]
    pending_count: usize,
    #[serde(rename = "retryingCount")]
    retrying_count: usize,
}

#[derive(Debug, Serialize)]
struct OverviewResponse {
    #[serde(flatten)]
    runtime: RuntimeStatusReport,
    #[serde(rename = "lastReconcileAt")]
    last_reconcile_at: Option<u64>,
    #[serde(rename = "certificateCount")]
    certificate_count: usize,
    #[serde(rename = "recentCertificates")]
    recent_certificates: Vec<CertificateRecord>,
    #[serde(rename = "chainManager")]
    chain_manager: Option<ChainManagerHeartbeat>,
    sp1: Option<Sp1Heartbeat>,
    #[serde(rename = "validatorProcesses")]
    validator_processes: Vec<ValidatorProcessSummary>,
}

#[derive(Debug)]
struct ApiError {
    status_code: StatusCode,
    message: String,
}

impl ApiError {
    fn bad_request(message: impl Into<String>) -> Self {
        Self { status_code: StatusCode::BAD_REQUEST, message: message.into() }
    }

    fn conflict(message: impl Into<String>) -> Self {
        Self { status_code: StatusCode::CONFLICT, message: message.into() }
    }

    fn internal(message: impl Into<String>) -> Self {
        Self { status_code: StatusCode::INTERNAL_SERVER_ERROR, message: message.into() }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let body = Json(serde_json::json!({ "error": self.message }));
        (self.status_code, body).into_response()
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt().init();

    let command_line_interface = CommandLineInterface::parse();
    let runtime = LoadedRuntime::load(command_line_interface.config)?;
    let application = Arc::new(NodeManagerApplication::new(runtime).await?);

    application.reconcile_once().await?;

    let reconcile_application = application.clone();
    tokio::spawn(async move {
        reconcile_loop(reconcile_application).await;
    });

    let application_state = ApplicationState { application: application.clone() };
    let router = Router::new()
        .route("/healthz", get(health_handler))
        .route("/overview", get(overview_handler))
        .route("/validators", get(validators_handler))
        .route("/certificates", post(certificates_handler))
        .route("/rewards/distribute", post(reward_distribution_handler))
        .route("/rewards/top-up", post(reward_top_up_handler))
        .layer(CorsLayer::very_permissive())
        .with_state(application_state);

    let bind_address: SocketAddr = application
        .runtime
        .config
        .services
        .node_manager
        .bind
        .parse()
        .wrap_err("invalid node-manager bind address")?;
    let listener = TcpListener::bind(bind_address).await?;
    info!(address = %bind_address, "node-manager listening");
    axum::serve(listener, router).await?;

    Ok(())
}

impl NodeManagerApplication {
    async fn new(runtime: LoadedRuntime) -> Result<Self> {
        runtime.ensure_runtime_directories()?;
        let owner_address = runtime.owner_address()?;
        let certificate_history = read_json_state_file::<Vec<CertificateRecord>>(
            &runtime.state_path("node-manager-certificates.json"),
        )
        .unwrap_or_default();

        for chain_config in &runtime.config.chains {
            let deploy_addresses = runtime.deployment(chain_config.id)?;
            let provider = read_provider(chain_config).await?;
            let validator_manager =
                IValidatorManager::new(deploy_addresses.validator_manager, provider);
            let validator_manager_owner =
                validator_manager.owner().call().await.wrap_err_with(|| {
                    format!("failed to read validator manager owner on chain {}", chain_config.id)
                })?;

            if validator_manager_owner != owner_address {
                bail!(
                    "validator manager owner mismatch on chain {}: expected {}, found {}",
                    chain_config.id,
                    owner_address,
                    validator_manager_owner
                );
            }
        }

        Ok(Self {
            runtime,
            last_reconcile_at: RwLock::new(None),
            certificate_history: RwLock::new(certificate_history),
        })
    }

    async fn health_response(&self) -> Result<HealthResponse> {
        Ok(HealthResponse {
            status: "ok",
            owner: self.runtime.owner_address()?,
            validator_count: self.runtime.validator_catalog.validators().len(),
            last_reconcile_at: *self.last_reconcile_at.read().await,
            certificate_count: self.certificate_history.read().await.len(),
        })
    }

    async fn validators_response(&self) -> Result<ValidatorsResponse> {
        let report = RuntimeStatusReporter::new(&self.runtime).generate().await?;
        Ok(ValidatorsResponse {
            last_reconcile_at: *self.last_reconcile_at.read().await,
            validators: report.validators,
        })
    }

    async fn overview_response(&self) -> Result<OverviewResponse> {
        let runtime_report = RuntimeStatusReporter::new(&self.runtime).generate().await?;
        let mut recent_certificates = self.certificate_history.read().await.clone();
        recent_certificates.reverse();
        recent_certificates.truncate(20);

        Ok(OverviewResponse {
            runtime: runtime_report,
            last_reconcile_at: *self.last_reconcile_at.read().await,
            certificate_count: self.certificate_history.read().await.len(),
            recent_certificates,
            chain_manager: read_json_state_file(&self.runtime.state_path("chain-manager.json")),
            sp1: read_json_state_file(&self.runtime.state_path("sp1.json"))
                .or_else(|| read_json_state_file(&self.runtime.state_path("sp1-state.json"))),
            validator_processes: self.validator_process_summaries(),
        })
    }

    async fn reconcile_once(&self) -> Result<u64> {
        let reconciler = ValidatorReconciler::new(&self.runtime);
        for chain_config in &self.runtime.config.chains {
            if chain_config.id == self.runtime.config.base_chain_id {
                continue;
            }
            for validator in self.runtime.validator_catalog.validators() {
                reconciler.reconcile_on_chain(chain_config.id, validator).await?;
            }
        }

        if let Err(error) = self.distribute_rewards_for_current_epoch().await {
            error!(?error, "automatic reward distribution failed");
        }

        let reconciled_at = unix_timestamp()?;
        *self.last_reconcile_at.write().await = Some(reconciled_at);
        self.write_heartbeat().await?;
        Ok(reconciled_at)
    }

    async fn issue_certificate_for(
        &self,
        certificate_request: CertificateRequest,
    ) -> Result<CertificateEnvelope, ApiError> {
        let validator = self
            .runtime
            .validator_catalog
            .by_address(certificate_request.validator)
            .map_err(|error| ApiError::bad_request(error.to_string()))?;
        self.runtime
            .chain(certificate_request.target_chain_id)
            .map_err(|error| ApiError::bad_request(error.to_string()))?;

        let base_status = self
            .validator_status_on_chain(self.runtime.config.base_chain_id, validator)
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;
        if base_status != ValidatorStatus::Active {
            return Err(ApiError::conflict(format!(
                "validator {} is not active on the base chain",
                validator.name
            )));
        }

        let target_status = self
            .validator_status_on_chain(certificate_request.target_chain_id, validator)
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;
        if target_status != ValidatorStatus::Active {
            ValidatorReconciler::new(&self.runtime)
                .reconcile_on_chain(certificate_request.target_chain_id, validator)
                .await
                .map_err(|error| ApiError::internal(error.to_string()))?;
        }

        let refreshed_target_status = self
            .validator_status_on_chain(certificate_request.target_chain_id, validator)
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;
        if refreshed_target_status != ValidatorStatus::Active {
            return Err(ApiError::conflict(format!(
                "validator {} is not active on target chain {}",
                validator.name, certificate_request.target_chain_id
            )));
        }

        let issued_at = unix_timestamp().map_err(|error| ApiError::internal(error.to_string()))?;
        let expires_at = issued_at + self.runtime.config.services.node_manager.certificate_ttl_secs;
        let certificate = issue_certificate(
            &self.runtime.owner_signer().map_err(|error| ApiError::internal(error.to_string()))?,
            validator.address().map_err(|error| ApiError::internal(error.to_string()))?,
            certificate_request.target_chain_id,
            issued_at,
            expires_at,
        )
        .await
        .map_err(|error| ApiError::internal(error.to_string()))?;

        self.record_certificate(&certificate)
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;

        Ok(certificate)
    }

    async fn top_up_reward_reserve(
        &self,
        reward_top_up_request: RewardTopUpRequest,
    ) -> Result<RewardTopUpResponse, ApiError> {
        let amount =
            parse_u256_hex_or_decimal(&reward_top_up_request.amount_wei).map_err(|error| {
                ApiError::bad_request(format!("invalid reward top-up amount: {error}"))
            })?;
        if amount.is_zero() {
            return Err(ApiError::bad_request("reward top-up amount must be greater than zero"));
        }

        let base_chain =
            self.runtime.base_chain().map_err(|error| ApiError::internal(error.to_string()))?;
        let base_deploy = self
            .runtime
            .deployment(base_chain.id)
            .map_err(|error| ApiError::internal(error.to_string()))?;
        let owner_signer =
            self.runtime.owner_signer().map_err(|error| ApiError::internal(error.to_string()))?;
        let owner_provider = signer_provider(base_chain, owner_signer.clone())
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;
        let stake_manager = IStakeManager::new(base_deploy.stake_manager, owner_provider.clone());
        let active_staking_config = stake_manager
            .ACTIVE_STAKING_CONFIG()
            .call()
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;
        let reward_token_address = active_staking_config.stakingToken;
        let reward_token = IERC20::new(reward_token_address, owner_provider);
        let owner_balance = reward_token
            .balanceOf(owner_signer.address())
            .call()
            .await
            .map_err(|error| ApiError::internal(error.to_string()))?;
        if owner_balance < amount {
            return Err(ApiError::conflict(format!(
                "owner balance {} is lower than requested reward top-up {}",
                owner_balance, amount
            )));
        }

        let approve_receipt = reward_token
            .approve(base_deploy.stake_manager, amount)
            .send()
            .await
            .map_err(|error| {
                ApiError::internal(format!("failed to approve reward top-up: {error}"))
            })?
            .get_receipt()
            .await
            .map_err(|error| {
                ApiError::internal(format!("failed waiting for reward top-up approval: {error}"))
            })?;
        ensure_successful_receipt("reward top-up approval", &approve_receipt)
            .map_err(|error| ApiError::internal(error.to_string()))?;

        let top_up_receipt = stake_manager
            .transferToken(reward_token_address, amount)
            .send()
            .await
            .map_err(|error| {
                ApiError::internal(format!("failed to top up reward reserve: {error}"))
            })?
            .get_receipt()
            .await
            .map_err(|error| {
                ApiError::internal(format!("failed waiting for reward top-up receipt: {error}"))
            })?;
        ensure_successful_receipt("reward reserve top-up", &top_up_receipt)
            .map_err(|error| ApiError::internal(error.to_string()))?;

        Ok(RewardTopUpResponse {
            status: "ok",
            chain_id: base_chain.id,
            stake_manager: base_deploy.stake_manager,
            reward_token: reward_token_address,
            amount_wei: amount.to_string(),
            approve_transaction_hash: approve_receipt.transaction_hash.to_string(),
            top_up_transaction_hash: top_up_receipt.transaction_hash.to_string(),
        })
    }

    async fn distribute_rewards_for_current_epoch(
        &self,
    ) -> Result<RewardDistributionResponse, ApiError> {
        let base_chain =
            self.runtime.base_chain().map_err(|error| ApiError::internal(error.to_string()))?;
        let base_deploy = self
            .runtime
            .deployment(base_chain.id)
            .map_err(|error| ApiError::internal(error.to_string()))?;
        let owner_provider = signer_provider(
            base_chain,
            self.runtime.owner_signer().map_err(|error| ApiError::internal(error.to_string()))?,
        )
        .await
        .map_err(|error| ApiError::internal(error.to_string()))?;
        let validator_manager =
            IValidatorManager::new(base_deploy.validator_manager, owner_provider.clone());
        let stake_manager = IStakeManager::new(base_deploy.stake_manager, owner_provider);

        let current_epoch = validator_manager.EPOCH().call().await.map_err(|error| {
            ApiError::internal(format!("failed to read current epoch: {error}"))
        })?;
        let active_validators =
            validator_manager.getActiveValidators().call().await.map_err(|error| {
                ApiError::internal(format!("failed to read active validators: {error}"))
            })?;

        if active_validators.is_empty() {
            return Ok(RewardDistributionResponse {
                status: "ok",
                chain_id: base_chain.id,
                epoch: current_epoch.to_string(),
                distributed: false,
                message: "No active validators to reward".to_owned(),
                transaction_hash: None,
            });
        }

        let mut should_distribute = false;
        for validator in active_validators {
            let balance =
                stake_manager.validatorBalance(validator).call().await.map_err(|error| {
                    ApiError::internal(format!(
                        "failed to read validator balance for {}: {error}",
                        validator
                    ))
                })?;
            if balance.stakeAmount > U256::ZERO && balance.lastRewardEpoch < current_epoch {
                should_distribute = true;
                break;
            }
        }

        if !should_distribute {
            return Ok(RewardDistributionResponse {
                status: "ok",
                chain_id: base_chain.id,
                epoch: current_epoch.to_string(),
                distributed: false,
                message: "Rewards already distributed for the current epoch".to_owned(),
                transaction_hash: None,
            });
        }

        let receipt = validator_manager
            .distributeRewards()
            .send()
            .await
            .map_err(|error| ApiError::internal(format!("failed to distribute rewards: {error}")))?
            .get_receipt()
            .await
            .map_err(|error| {
                ApiError::internal(format!(
                    "failed waiting for reward distribution receipt: {error}"
                ))
            })?;
        ensure_successful_receipt("reward distribution", &receipt)
            .map_err(|error| ApiError::internal(error.to_string()))?;

        Ok(RewardDistributionResponse {
            status: "ok",
            chain_id: base_chain.id,
            epoch: current_epoch.to_string(),
            distributed: true,
            message: "Rewards distributed for the current epoch".to_owned(),
            transaction_hash: Some(receipt.transaction_hash.to_string()),
        })
    }

    async fn validator_status_on_chain(
        &self,
        chain_id: u64,
        validator: &DevValidator,
    ) -> Result<ValidatorStatus> {
        let chain_config = self.runtime.chain(chain_id)?;
        let deploy_addresses = self.runtime.deployment(chain_id)?;
        let provider = read_provider(chain_config).await?;
        let validator_manager =
            IValidatorManager::new(deploy_addresses.validator_manager, provider);
        let validator_info =
            validator_manager.getValidator(validator.address()?).call().await.wrap_err_with(
                || format!("failed to read validator {} on chain {}", validator.name, chain_id),
            )?;
        Ok(ValidatorStatus::from(validator_info.status))
    }

    async fn record_certificate(&self, certificate: &CertificateEnvelope) -> Result<()> {
        let mut certificate_history = self.certificate_history.write().await;
        certificate_history.push(CertificateRecord {
            validator: certificate.validator,
            target_chain_id: certificate.target_chain_id,
            issued_at: certificate.issued_at,
            expires_at: certificate.expires_at,
            certificate_hex: certificate.certificate_hex.clone(),
            signer: certificate.signer,
        });
        write_state_file(&self.runtime, "node-manager-certificates.json", &*certificate_history)?;
        drop(certificate_history);
        self.write_heartbeat().await?;
        Ok(())
    }

    async fn write_heartbeat(&self) -> Result<()> {
        let heartbeat = HeartbeatState {
            status: "ok",
            owner: self.runtime.owner_address()?,
            validator_count: self.runtime.validator_catalog.validators().len(),
            last_reconcile_at: *self.last_reconcile_at.read().await,
            certificate_count: self.certificate_history.read().await.len(),
        };
        write_state_file(&self.runtime, "node-manager.json", &heartbeat)
    }

    fn validator_process_summaries(&self) -> Vec<ValidatorProcessSummary> {
        self.runtime
            .validator_catalog
            .validators()
            .iter()
            .map(|validator| {
                let state_path =
                    self.runtime.state_path(format!("validators/{}.json", validator.name));
                match read_json_state_file::<ValidatorProcessState>(&state_path) {
                    Some(process_state) => {
                        let submitted_count = process_state
                            .entries
                            .values()
                            .filter(|entry| entry.status == "submitted")
                            .count();
                        let pending_count = process_state
                            .entries
                            .values()
                            .filter(|entry| entry.status == "pending")
                            .count();
                        let retrying_count = process_state
                            .entries
                            .values()
                            .filter(|entry| entry.retry_count > 0)
                            .count();

                        ValidatorProcessSummary {
                            validator: process_state.validator,
                            last_heartbeat_at: process_state.last_heartbeat_at,
                            last_error: process_state.last_error,
                            submitted_count,
                            pending_count,
                            retrying_count,
                        }
                    }
                    None => ValidatorProcessSummary {
                        validator: validator.name.clone(),
                        last_heartbeat_at: None,
                        last_error: Some("validator process has not written state".to_owned()),
                        submitted_count: 0,
                        pending_count: 0,
                        retrying_count: 0,
                    },
                }
            })
            .collect()
    }
}

async fn reconcile_loop(application: Arc<NodeManagerApplication>) {
    let interval_seconds = application.runtime.config.services.node_manager.reconcile_interval_secs;
    loop {
        sleep(Duration::from_secs(interval_seconds)).await;
        if let Err(error) = application.reconcile_once().await {
            error!(?error, "node-manager reconcile failed");
        }
    }
}

async fn health_handler(
    State(application_state): State<ApplicationState>,
) -> Result<Json<HealthResponse>, ApiError> {
    application_state
        .application
        .health_response()
        .await
        .map(Json)
        .map_err(|error| ApiError::internal(error.to_string()))
}

async fn overview_handler(
    State(application_state): State<ApplicationState>,
) -> Result<Json<OverviewResponse>, ApiError> {
    application_state
        .application
        .overview_response()
        .await
        .map(Json)
        .map_err(|error| ApiError::internal(error.to_string()))
}

async fn validators_handler(
    State(application_state): State<ApplicationState>,
) -> Result<Json<ValidatorsResponse>, ApiError> {
    application_state
        .application
        .validators_response()
        .await
        .map(Json)
        .map_err(|error| ApiError::internal(error.to_string()))
}

async fn certificates_handler(
    State(application_state): State<ApplicationState>,
    Json(certificate_request): Json<CertificateRequest>,
) -> Result<Json<CertificateEnvelope>, ApiError> {
    application_state.application.issue_certificate_for(certificate_request).await.map(Json)
}

async fn reward_top_up_handler(
    State(application_state): State<ApplicationState>,
    Json(reward_top_up_request): Json<RewardTopUpRequest>,
) -> Result<Json<RewardTopUpResponse>, ApiError> {
    application_state.application.top_up_reward_reserve(reward_top_up_request).await.map(Json)
}

async fn reward_distribution_handler(
    State(application_state): State<ApplicationState>,
) -> Result<Json<RewardDistributionResponse>, ApiError> {
    application_state.application.distribute_rewards_for_current_epoch().await.map(Json)
}

fn read_json_state_file<T: DeserializeOwned>(path: &std::path::Path) -> Option<T> {
    let bytes = fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

#[cfg(test)]
mod tests {
    use super::{
        CertificateRequest, HealthResponse, RewardDistributionResponse, RewardTopUpRequest,
        RewardTopUpResponse,
    };
    use alloy::primitives::address;

    #[test]
    fn certificate_request_uses_target_chain_id_wire_name() {
        let request: CertificateRequest = serde_json::from_value(serde_json::json!({
            "validator": "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
            "targetChainId": 8453
        }))
        .expect("request should deserialize");

        assert_eq!(request.validator, address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"));
        assert_eq!(request.target_chain_id, 8453);
    }

    #[test]
    fn health_response_serializes_runtime_fields() {
        let response = HealthResponse {
            status: "ok",
            owner: address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"),
            validator_count: 5,
            last_reconcile_at: Some(1_700_000_000),
            certificate_count: 12,
        };

        let value = serde_json::to_value(response).expect("response should serialize");
        assert_eq!(value["status"], "ok");
        assert_eq!(value["validatorCount"], 5);
        assert_eq!(value["lastReconcileAt"], 1_700_000_000u64);
        assert_eq!(value["certificateCount"], 12);
    }

    #[test]
    fn reward_top_up_request_uses_amount_wei_wire_name() {
        let request: RewardTopUpRequest = serde_json::from_value(serde_json::json!({
            "amountWei": "1000000000000000000"
        }))
        .expect("request should deserialize");

        assert_eq!(request.amount_wei, "1000000000000000000");
    }

    #[test]
    fn reward_top_up_response_serializes_wire_fields() {
        let response = RewardTopUpResponse {
            status: "ok",
            chain_id: 31339,
            stake_manager: address!("5FbDB2315678afecb367f032d93F642f64180aa3"),
            reward_token: address!("9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"),
            amount_wei: "1000000000000000000".to_owned(),
            approve_transaction_hash:
                "0x1111111111111111111111111111111111111111111111111111111111111111".to_owned(),
            top_up_transaction_hash:
                "0x2222222222222222222222222222222222222222222222222222222222222222".to_owned(),
        };

        let value = serde_json::to_value(response).expect("response should serialize");
        assert_eq!(value["chainId"], 31339u64);
        assert_eq!(value["amountWei"], "1000000000000000000");
        assert_eq!(
            value["approveTransactionHash"],
            "0x1111111111111111111111111111111111111111111111111111111111111111"
        );
        assert_eq!(
            value["topUpTransactionHash"],
            "0x2222222222222222222222222222222222222222222222222222222222222222"
        );
    }

    #[test]
    fn reward_distribution_response_serializes_wire_fields() {
        let response = RewardDistributionResponse {
            status: "ok",
            chain_id: 31339,
            epoch: "3".to_owned(),
            distributed: true,
            message: "Rewards distributed for the current epoch".to_owned(),
            transaction_hash: Some(
                "0x3333333333333333333333333333333333333333333333333333333333333333".to_owned(),
            ),
        };

        let value = serde_json::to_value(response).expect("response should serialize");
        assert_eq!(value["chainId"], 31339u64);
        assert_eq!(value["epoch"], "3");
        assert_eq!(value["distributed"], true);
        assert_eq!(
            value["transactionHash"],
            "0x3333333333333333333333333333333333333333333333333333333333333333"
        );
    }
}
