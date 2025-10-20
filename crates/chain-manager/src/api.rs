use std::sync::Arc;

use alloy::{
    consensus::Header,
    primitives::B256,
    providers::{Provider, ProviderBuilder},
    rpc::types::{eth::TransactionReceipt, BlockNumberOrTag},
};
use dashmap::DashMap;
use jsonrpsee::{
    core::{async_trait, RpcResult},
    proc_macros::rpc,
    types::ErrorObjectOwned,
};
use thiserror::Error;

#[rpc(server, client)]
pub trait ChainManager {
    #[method(name = "finalisedHeader")]
    async fn finalised_header(&self, chain_id: u64, at: BlockNumberOrTag) -> RpcResult<Header>;

    #[method(name = "transactionReceipt")]
    async fn transaction_receipt(
        &self,
        chain_id: u64,
        tx_hash: B256,
    ) -> RpcResult<Option<TransactionReceipt>>;
}

#[derive(Error, Debug, Clone)]
pub enum ChainManagerError {
    #[error("The chain id used was not part of the chains configured")]
    ChainIdNotFound { reason: String, chain_id: u64 },
    #[error("The node returned a custom error")]
    NodeFailure { reason: String, chain_id: u64 },
    #[error("We failed to init a provier")]
    ProviderFailure { reason: String, chain_id: u64 },
    #[error("We use this for generic errors")]
    GenericFailure { reason: String, chain_id: u64 },
}
#[derive(Clone, Debug, Default)]
pub struct ChainConfig {
    chain_id: u64,
    rpc_url: String,
}

/// We dont need to create a provider since validators
/// Are going to query on demand so we init a provider based on chn id
pub struct ChainManagerImpl {
    configs: Vec<ChainConfig>,
    providers: Arc<DashMap<u64, Arc<dyn Provider>>>,
}

impl From<ChainManagerError> for ErrorObjectOwned {
    fn from(error: ChainManagerError) -> Self {
        match error {
            ChainManagerError::ChainIdNotFound { reason, chain_id } => {
                ErrorObjectOwned::owned(-4004, reason, Some(chain_id))
            }
            ChainManagerError::NodeFailure { reason, chain_id } => {
                ErrorObjectOwned::owned(-4005, reason, Some(chain_id))
            }
            ChainManagerError::ProviderFailure { reason, chain_id } => {
                ErrorObjectOwned::owned(-4006, reason, Some(chain_id))
            }
            ChainManagerError::GenericFailure { reason, chain_id } => {
                ErrorObjectOwned::owned(-4007, reason, Some(chain_id))
            }
        }
    }
}

impl ChainManagerImpl {
    pub async fn get_provider(
        &self,
        chain_id: u64,
    ) -> Result<Arc<dyn Provider>, ChainManagerError> {
        if let Some(provider) = self.providers.get(&chain_id) {
            return Ok(provider.clone())
        }
        let chain_config =
            self.configs.iter().find(|config| config.chain_id == chain_id).ok_or_else(|| {
                ChainManagerError::ChainIdNotFound {
                    reason: "Chain id not configured".into(),
                    chain_id,
                }
            })?;

        let url = chain_config.rpc_url.as_str();
        let provider = ProviderBuilder::new().connect(url).await.map_err(|error| {
            ChainManagerError::GenericFailure {
                reason: format!("Something went wrong while initialising provider {error:?}")
                    .into(),
                chain_id,
            }
        })?;
        let provider = Arc::new(provider);
        self.providers.insert(chain_id, provider.clone());
        Ok(provider)
    }
}

#[async_trait]
impl ChainManagerServer for ChainManagerImpl {
    async fn finalised_header(&self, chain_id: u64, at: BlockNumberOrTag) -> RpcResult<Header> {
        let provider = self.get_provider(chain_id).await.map_err(|error| error);

        let header = provider.unwrap().get_block_by_number(at).full().await.map_err(|error| {
            ChainManagerError::GenericFailure {
                reason: format!("Something went wrong while getting finalised header {error:?}")
                    .into(),
                chain_id,
            }
        });

        Ok(header.unwrap().unwrap().header.into())
    }
    async fn transaction_receipt(
        &self,
        chain_id: u64,
        tx_hash: B256,
    ) -> RpcResult<Option<TransactionReceipt>> {
        let provider = self.get_provider(chain_id).await.map_err(|error| error);

        let receipt = provider.unwrap().get_transaction_receipt(tx_hash).await.map_err(|error| {
            ChainManagerError::GenericFailure {
                reason: format!("Something went wrong while getting transaction receipt {error:?}")
                    .into(),
                chain_id,
            }
        });

        Ok(receipt.unwrap())
    }
}

impl ChainManagerImpl {
    fn new(configs: Vec<ChainConfig>) -> Self {
        Self { configs, providers: Default::default() }
    }
}

#[cfg(test)]
mod test {
    use crate::{
        api::{ChainManagerServer, Header},
        ChainConfig, ChainManagerClient, ChainManagerImpl,
    };
    use alloy::{
        network::TransactionBuilder,
        node_bindings::{Anvil, AnvilInstance},
        primitives::U256,
        providers::{Provider, ProviderBuilder},
        rpc::types::{eth::TransactionRequest, BlockNumberOrTag},
    };
    use jsonrpsee::{http_client::HttpClientBuilder, rpc_params, server::ServerBuilder};
    use jsonrpsee_core::client::ClientT;
    use serial_test::serial;
    use std::net::SocketAddr;

    fn create_anvil_instances(count: u16, base_port: u16) -> Vec<AnvilInstance> {
        let mut instances = Vec::new();
        for i in 0..count {
            let port = base_port + i;
            let instance = Anvil::new()
                .port(port)
                .chain_id((i + 1).into())
                .try_spawn()
                .expect(&format!("Failed to spawn anvil instance on port {}", port));
            instances.push(instance);
        }
        instances
    }

    fn create_configs(anvils: &[AnvilInstance]) -> Vec<ChainConfig> {
        anvils
            .iter()
            .map(|anvil| ChainConfig { rpc_url: anvil.endpoint(), chain_id: anvil.chain_id() })
            .collect()
    }

    async fn create_start_server(
        manager: impl ChainManagerServer,
        address: &str,
    ) -> Result<
        (jsonrpsee::server::ServerHandle, jsonrpsee::http_client::HttpClient),
        Box<dyn std::error::Error>,
    > {
        let server_addr: SocketAddr = address.parse()?;
        let server = ServerBuilder::default().build(server_addr).await?;
        let handle = server.start(manager.into_rpc());
        let client = HttpClientBuilder::default().build(format!("http://{}", address))?;
        Ok((handle, client))
    }

    #[tokio::test]
    #[serial]
    async fn test_basic_header_retrieval() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(1, 8545);
        let configs = create_configs(&anvils);
        let manager = ChainManagerImpl::new(configs);
        let (handle, client) = create_start_server(manager, "127.0.0.1:3000").await?;

        let chain_id = anvils[0].chain_id();
        let header: Header = client
            .request("finalisedHeader", rpc_params!(chain_id, BlockNumberOrTag::Latest))
            .await?;

        assert_eq!(header.number, 0, "Should start at genesis");

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }

    #[tokio::test]
    #[serial]
    async fn test_provider_caching() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(1, 8545);
        let configs = create_configs(&anvils);
        let manager = ChainManagerImpl::new(configs);
        let (handle, client) = create_start_server(manager, "127.0.0.1:3000").await?;

        let chain_id = anvils[0].chain_id();

        for _ in 0..5 {
            let header: Header = client
                .request("finalisedHeader", rpc_params!(chain_id, BlockNumberOrTag::Latest))
                .await?;
            assert_eq!(header.number, 0);
        }

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }

    #[tokio::test]
    #[serial]
    async fn test_multi_chain_routing() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(2, 8545);
        let configs = create_configs(&anvils);
        let manager = ChainManagerImpl::new(configs);
        let (handle, client) = create_start_server(manager, "127.0.0.1:3000").await?;

        let header_1: Header =
            client.request("finalisedHeader", rpc_params!(1u64, BlockNumberOrTag::Latest)).await?;

        let header_2: Header =
            client.request("finalisedHeader", rpc_params!(2u64, BlockNumberOrTag::Latest)).await?;

        assert_eq!(header_1.number, 0);
        assert_eq!(header_2.number, 0);

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }

    #[tokio::test]
    #[serial]
    async fn test_transaction_receipt() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(1, 8545);
        let configs = create_configs(&anvils);
        let manager = ChainManagerImpl::new(configs);
        let (handle, client) = create_start_server(manager, "127.0.0.1:3000").await?;

        let signer: alloy::signers::local::PrivateKeySigner = anvils[0].keys()[0].clone().into();
        let provider =
            ProviderBuilder::new().wallet(signer.clone()).connect_http(anvils[0].endpoint_url());

        let tx = TransactionRequest::default()
            .with_from(signer.address())
            .with_to(anvils[0].addresses()[1])
            .with_value(U256::from(1000));

        let receipt = provider.send_transaction(tx).await?.get_receipt().await?;
        let tx_hash = receipt.transaction_hash;

        let manager_receipt = client
            .transaction_receipt(anvils[0].chain_id(), tx_hash)
            .await?
            .expect("Receipt should exist");

        assert_eq!(manager_receipt.transaction_hash, tx_hash);
        assert!(manager_receipt.status());

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }

    #[tokio::test]
    #[serial]
    async fn test_unknown_chain_error() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(1, 8545);
        let configs = create_configs(&anvils);
        let manager = ChainManagerImpl::new(configs);
        let (handle, client) = create_start_server(manager, "127.0.0.1:3000").await?;

        let result: Result<Header, _> =
            client.request("finalisedHeader", rpc_params!(9999u64, BlockNumberOrTag::Latest)).await;

        assert!(result.is_err());
        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }
}
