use alloy_consensus::Header;
use alloy_eips::eip2718::Encodable2718;
use alloy_primitives::{Bytes, B256};
use alloy_provider::{Provider, ProviderBuilder};
use alloy_rlp::encode;
use alloy_rpc_types::{eth::TransactionReceipt, BlockNumberOrTag};
use alloy_trie::root::adjust_index_for_rlp;
use dashmap::DashMap;
use jsonrpsee::{
    core::{async_trait, RpcResult},
    http_client::HttpClientBuilder,
    proc_macros::rpc,
    server::ServerBuilder,
    types::ErrorObjectOwned,
};
use reth_trie::{HashBuilder, Nibbles};
use reth_trie_common::proof::ProofRetainer;
use std::{collections::HashMap, fmt::Debug, net::SocketAddr, sync::Arc};
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

    #[method(name = "receiptProof")]
    async fn receipt_proof(
        &self,
        chain_id: u64,
        tx_hash: B256,
    ) -> RpcResult<Option<ReceiptWithProof>>;

    #[method(name = "blockReceiptsWithProofs")]
    async fn block_receipts_with_proofs(
        &self,
        chain_id: u64,
        block_number: u64,
    ) -> RpcResult<HashMap<B256, ReceiptWithProof>>;
}

#[derive(Error, Debug, Clone)]
pub enum ChainManagerError {
    #[error("Chain ID {chain_id} not configured: {reason}")]
    ChainIdNotFound { reason: String, chain_id: u64 },

    #[error("Node failure for chain {chain_id}: {reason}")]
    NodeFailure { reason: String, chain_id: u64 },

    #[error("Provider initialization failed for chain {chain_id}: {reason}")]
    ProviderFailure { reason: String, chain_id: u64 },

    #[error("Trie operation failed for chain {chain_id}: {reason}")]
    TrieError { reason: String, chain_id: u64 },

    #[error(
        "Receipts root mismatch for chain {chain_id}: computed={computed:?}, expected={expected:?}"
    )]
    RootMismatch { computed: B256, expected: B256, chain_id: u64 },

    #[error("Generic failure for chain {chain_id}: {reason}")]
    GenericFailure { reason: String, chain_id: u64 },
}

#[derive(Clone, Debug, Default)]
pub struct ChainConfig {
    pub chain_id: u64,
    pub rpc_url: String,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ReceiptWithProof {
    /// Block header containing the receipts_root to verify against
    #[serde(with = "header_serde")]
    pub header: Header,

    /// The full transaction receipt (RPC type)
    pub receipt: TransactionReceipt,

    /// Zero-based index of this transaction within the block
    pub transaction_index: u64,

    /// RLP-encoded trie nodes forming the Merkle proof path
    pub proof_nodes: Vec<Bytes>,
}

mod header_serde {
    use alloy_consensus::Header;
    use serde::{Deserialize, Deserializer, Serialize, Serializer};

    pub(super) fn serialize<S>(header: &Header, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let json = serde_json::to_value(header).map_err(serde::ser::Error::custom)?;
        json.serialize(serializer)
    }

    pub(super) fn deserialize<'de, D>(deserializer: D) -> Result<Header, D::Error>
    where
        D: Deserializer<'de>,
    {
        let json = serde_json::Value::deserialize(deserializer)?;
        serde_json::from_value(json).map_err(serde::de::Error::custom)
    }
}

/// Patricia Merkle Trie for receipts with proof generation
#[derive(Debug)]
pub struct ReceiptsTrie {
    receipts: Vec<TransactionReceipt>,
    root: B256,
}

impl ReceiptsTrie {
    pub fn new(receipts: Vec<TransactionReceipt>) -> Result<Self, ChainManagerError> {
        let root = Self::compute_root(&receipts)?;
        Ok(Self { receipts, root })
    }

    /// Compute receipts root using HashBuilder.
    ///
    /// Receipts are committed via `encode_2718` (EIP-2718 envelope bytes: type prefix + RLP)
    /// rather than `encode` / `network_encode`, which adds an extra RLP length header for typed
    /// receipts that is only used in the p2p wire protocol and breaks trie root computation.
    ///
    /// Leaves must be inserted in ascending nibble-path order.  Because RLP(0) = 0x80 whose
    /// nibbles [8,0] sort *after* RLP(1..=127), the natural 0,1,2,… traversal order is wrong.
    /// `adjust_index_for_rlp` produces a permutation that yields ascending nibble order.
    fn compute_root(receipts: &[TransactionReceipt]) -> Result<B256, ChainManagerError> {
        let mut hash_builder = HashBuilder::default();
        let items_len = receipts.len();

        for i in 0..items_len {
            let sorted_index = adjust_index_for_rlp(i, items_len);

            let key = encode(sorted_index);
            let key_nibbles = Nibbles::unpack(&key);

            let mut receipt_buf = Vec::new();
            let envelope = receipts[sorted_index].inner.clone().into_primitives_receipt();
            envelope.encode_2718(&mut receipt_buf);

            hash_builder.add_leaf(key_nibbles, &receipt_buf);
        }

        Ok(hash_builder.root())
    }

    pub fn root(&self) -> B256 {
        self.root
    }

    pub fn get_proof(&self, index: u64) -> Result<Vec<Bytes>, ChainManagerError> {
        if index >= self.receipts.len() as u64 {
            return Err(ChainManagerError::TrieError {
                reason: format!(
                    "Receipt index {} out of bounds (total: {})",
                    index,
                    self.receipts.len()
                ),
                chain_id: 0,
            });
        }

        let target_key = encode(index as usize);
        let target_nibbles = Nibbles::unpack(&target_key);

        let proof_retainer = ProofRetainer::from_iter([target_nibbles]);
        let mut hash_builder = HashBuilder::default().with_proof_retainer(proof_retainer);

        let items_len = self.receipts.len();
        for i in 0..items_len {
            let sorted_index = adjust_index_for_rlp(i, items_len);

            let k = encode(sorted_index);
            let k_nibbles = Nibbles::unpack(&k);

            let mut receipt_buf = Vec::new();
            let envelope = self.receipts[sorted_index].inner.clone().into_primitives_receipt();
            envelope.encode_2718(&mut receipt_buf);

            hash_builder.add_leaf(k_nibbles, &receipt_buf);
        }

        // root() finalizes the trie, triggering the proof retainer to capture all
        // nodes on the proof path. take_proof_nodes() must be called after root().
        hash_builder.root();

        let proof_nodes_map = hash_builder.take_proof_nodes();
        let mut proof_entries: Vec<_> = proof_nodes_map.into_inner().into_iter().collect();
        proof_entries.sort_by(|(left_path, _), (right_path, _)| left_path.cmp(right_path));
        let proof_nodes =
            proof_entries.into_iter().map(|(_, node_data)| Bytes::from(node_data)).collect();

        Ok(proof_nodes)
    }
}

/// We dont need to create a provider since validators
/// Are going to query on demand so we init a provider based on chn id
#[derive(Clone, Default)]
pub struct ChainManagerImpl {
    pub configs: Vec<ChainConfig>,
    pub providers: Arc<DashMap<u64, Arc<dyn Provider>>>,
}

impl Debug for ChainManagerImpl {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ChainManagerImpl")
            .field("configs", &self.configs)
            .field("providers", &"<Provider map>")
            .finish()
    }
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
            ChainManagerError::TrieError { reason, chain_id } => {
                ErrorObjectOwned::owned(-4008, reason, Some(chain_id))
            }
            ChainManagerError::RootMismatch { computed, expected, chain_id } => {
                ErrorObjectOwned::owned(
                    -4009,
                    format!("Root mismatch: computed={:?}, expected={:?}", computed, expected),
                    Some(chain_id),
                )
            }
            ChainManagerError::GenericFailure { reason, chain_id } => {
                ErrorObjectOwned::owned(-4007, reason, Some(chain_id))
            }
        }
    }
}

impl ChainManagerImpl {
    pub fn new(configs: Vec<ChainConfig>) -> Self {
        Self { configs, providers: Default::default() }
    }

    pub async fn create_start_server(
        &self,
        address: &str,
    ) -> Result<
        (jsonrpsee::server::ServerHandle, jsonrpsee::http_client::HttpClient),
        Box<dyn std::error::Error>,
    > {
        let server_addr: SocketAddr = address.parse()?;
        let server = ServerBuilder::default().build(server_addr).await?;
        let handle = server.start(self.clone().into_rpc());
        let client = HttpClientBuilder::default().build(format!("http://{}", address))?;
        Ok((handle, client))
    }

    async fn get_provider(&self, chain_id: u64) -> Result<Arc<dyn Provider>, ChainManagerError> {
        if let Some(provider) = self.providers.get(&chain_id) {
            return Ok(provider.clone());
        }

        let chain_config =
            self.configs.iter().find(|config| config.chain_id == chain_id).ok_or_else(|| {
                ChainManagerError::ChainIdNotFound {
                    reason: "Chain ID not in configuration".into(),
                    chain_id,
                }
            })?;

        let provider =
            ProviderBuilder::new().connect(&chain_config.rpc_url).await.map_err(|error| {
                ChainManagerError::ProviderFailure {
                    reason: format!("Failed to connect: {:?}", error),
                    chain_id,
                }
            })?;

        let provider = Arc::new(provider);
        self.providers.insert(chain_id, provider.clone());

        tracing::info!("Created new provider for chain {}", chain_id);

        Ok(provider)
    }

    async fn fetch_all_receipts_for_block(
        &self,
        provider: &Arc<dyn Provider>,
        block_number: u64,
        tx_hashes: &[B256],
        chain_id: u64,
    ) -> Result<Vec<TransactionReceipt>, ChainManagerError> {
        match provider.get_block_receipts(block_number.into()).await {
            Ok(Some(receipts)) if !receipts.is_empty() => {
                tracing::debug!("Fetched {} receipts via eth_getBlockReceipts", receipts.len());
                return Ok(receipts);
            }
            _ => {
                tracing::debug!("Falling back to individual receipt fetching");
            }
        }

        if tx_hashes.is_empty() {
            return Ok(Vec::new());
        }

        let mut receipts = Vec::with_capacity(tx_hashes.len());

        for tx_hash in tx_hashes {
            let receipt = provider
                .get_transaction_receipt(*tx_hash)
                .await
                .map_err(|e| ChainManagerError::NodeFailure {
                    reason: format!("Failed to fetch receipt: {:?}", e),
                    chain_id,
                })?
                .ok_or_else(|| ChainManagerError::NodeFailure {
                    reason: format!("Receipt not found for tx {}", tx_hash),
                    chain_id,
                })?;

            receipts.push(receipt);
        }

        Ok(receipts)
    }

    fn build_receipts_trie(
        &self,
        receipts: &[TransactionReceipt],
        chain_id: u64,
    ) -> Result<ReceiptsTrie, ChainManagerError> {
        ReceiptsTrie::new(receipts.to_vec()).map_err(|e| ChainManagerError::TrieError {
            reason: format!("Trie construction failed: {:?}", e),
            chain_id,
        })
    }

    async fn prepare_receipts_trie(
        &self,
        chain_id: u64,
        block_number: u64,
    ) -> Result<(Header, Vec<TransactionReceipt>, ReceiptsTrie), ChainManagerError> {
        let provider = self.get_provider(chain_id).await?;

        let block = provider
            .get_block_by_number(block_number.into())
            .await
            .map_err(|e| ChainManagerError::NodeFailure {
                reason: format!("Failed to fetch block: {:?}", e),
                chain_id,
            })?
            .ok_or_else(|| ChainManagerError::NodeFailure {
                reason: format!("Block {} not found", block_number),
                chain_id,
            })?;

        let header: Header = block.header.into();
        let tx_hashes: Vec<B256> = block.transactions.hashes().collect();

        let receipts = self
            .fetch_all_receipts_for_block(&provider, block_number, &tx_hashes, chain_id)
            .await?;

        let trie = self.build_receipts_trie(&receipts, chain_id)?;

        let computed_root = trie.root();
        let expected_root = header.receipts_root;

        if computed_root != expected_root {
            return Err(ChainManagerError::RootMismatch {
                computed: computed_root,
                expected: expected_root,
                chain_id,
            });
        }

        tracing::info!("Verified receipts trie for block {} on chain {}", block_number, chain_id);

        Ok((header, receipts, trie))
    }
}

#[async_trait]
impl ChainManagerServer for ChainManagerImpl {
    async fn finalised_header(&self, chain_id: u64, at: BlockNumberOrTag) -> RpcResult<Header> {
        let provider = self.get_provider(chain_id).await.map_err(ErrorObjectOwned::from)?;

        let block = provider
            .get_block_by_number(at)
            .await
            .map_err(|e| {
                ErrorObjectOwned::from(ChainManagerError::NodeFailure {
                    reason: format!("Failed to fetch block: {:?}", e),
                    chain_id,
                })
            })?
            .ok_or_else(|| {
                ErrorObjectOwned::from(ChainManagerError::NodeFailure {
                    reason: "Block not found".into(),
                    chain_id,
                })
            })?;

        Ok(block.header.into())
    }

    async fn transaction_receipt(
        &self,
        chain_id: u64,
        tx_hash: B256,
    ) -> RpcResult<Option<TransactionReceipt>> {
        let provider = self.get_provider(chain_id).await.map_err(ErrorObjectOwned::from)?;

        let receipt = provider.get_transaction_receipt(tx_hash).await.map_err(|e| {
            ErrorObjectOwned::from(ChainManagerError::NodeFailure {
                reason: format!("Failed to fetch receipt: {:?}", e),
                chain_id,
            })
        })?;

        Ok(receipt)
    }

    async fn receipt_proof(
        &self,
        chain_id: u64,
        tx_hash: B256,
    ) -> RpcResult<Option<ReceiptWithProof>> {
        let provider = self.get_provider(chain_id).await.map_err(ErrorObjectOwned::from)?;

        let receipt = match provider.get_transaction_receipt(tx_hash).await {
            Ok(Some(r)) => r,
            Ok(None) => return Ok(None),
            Err(e) => {
                return Err(ErrorObjectOwned::from(ChainManagerError::NodeFailure {
                    reason: format!("Failed to fetch receipt: {:?}", e),
                    chain_id,
                }))
            }
        };

        let block_number = receipt.block_number.ok_or_else(|| {
            ErrorObjectOwned::from(ChainManagerError::GenericFailure {
                reason: "Receipt missing block_number".into(),
                chain_id,
            })
        })?;

        let tx_index = receipt.transaction_index.ok_or_else(|| {
            ErrorObjectOwned::from(ChainManagerError::GenericFailure {
                reason: "Receipt missing transaction_index".into(),
                chain_id,
            })
        })?;

        let (header, _receipts, trie) = self
            .prepare_receipts_trie(chain_id, block_number)
            .await
            .map_err(ErrorObjectOwned::from)?;

        let proof_nodes = trie.get_proof(tx_index).map_err(ErrorObjectOwned::from)?;

        Ok(Some(ReceiptWithProof { header, receipt, transaction_index: tx_index, proof_nodes }))
    }

    async fn block_receipts_with_proofs(
        &self,
        chain_id: u64,
        block_number: u64,
    ) -> RpcResult<HashMap<B256, ReceiptWithProof>> {
        let (header, receipts, trie) = self
            .prepare_receipts_trie(chain_id, block_number)
            .await
            .map_err(ErrorObjectOwned::from)?;

        let mut results = HashMap::with_capacity(receipts.len());

        for (idx, receipt) in receipts.into_iter().enumerate() {
            let proof_nodes = trie.get_proof(idx as u64).map_err(ErrorObjectOwned::from)?;

            results.insert(
                receipt.transaction_hash,
                ReceiptWithProof {
                    header: header.clone(),
                    receipt,
                    transaction_index: idx as u64,
                    proof_nodes,
                },
            );
        }

        Ok(results)
    }
}

#[cfg(test)]
mod test {
    use super::*;
    use alloy_network::TransactionBuilder;
    use alloy_node_bindings::{Anvil, AnvilInstance};
    use alloy_primitives::U256;
    use alloy_provider::ProviderBuilder;
    use alloy_rpc_types::TransactionRequest;
    use alloy_signer_local::PrivateKeySigner;
    use serial_test::serial;

    fn create_anvil_instances(count: u16, base_port: u16) -> Vec<AnvilInstance> {
        let mut instances = Vec::new();
        for i in 0..count {
            let port = base_port + i;
            let instance = Anvil::new()
                .port(port)
                .chain_id((i + 1).into())
                .try_spawn()
                .unwrap_or_else(|_| panic!("Failed to spawn anvil on port {}", port));
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

    #[tokio::test]
    #[serial]
    async fn test_receipt_proof() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(1, 8547);
        let configs = create_configs(&anvils);
        let (handle, client) =
            ChainManagerImpl::new(configs).create_start_server("127.0.0.1:3000").await?;

        let signer: PrivateKeySigner = anvils[0].keys()[0].clone().into();
        let provider =
            ProviderBuilder::new().wallet(signer.clone()).connect_http(anvils[0].endpoint_url());

        let tx = TransactionRequest::default()
            .with_from(signer.address())
            .with_to(anvils[0].addresses()[1])
            .with_value(U256::from(1000));

        let receipt = provider.send_transaction(tx).await?.get_receipt().await?;
        let tx_hash = receipt.transaction_hash;

        let proof: ReceiptWithProof =
            client.receipt_proof(anvils[0].chain_id(), tx_hash).await?.expect("Proof should exist");

        assert_eq!(proof.receipt.transaction_hash, tx_hash);
        assert!(!proof.proof_nodes.is_empty());

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }

    #[tokio::test]
    #[serial]
    async fn test_receipt_proof_missing_tx_returns_none() -> Result<(), Box<dyn std::error::Error>>
    {
        let anvils = create_anvil_instances(1, 8549);
        let configs = create_configs(&anvils);
        let (handle, client) =
            ChainManagerImpl::new(configs).create_start_server("127.0.0.1:3002").await?;

        let missing_tx = B256::from([0x11u8; 32]);
        let proof = client.receipt_proof(anvils[0].chain_id(), missing_tx).await?;
        assert!(proof.is_none());

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }

    #[tokio::test]
    #[serial]
    async fn test_unconfigured_chain_id_errors() -> Result<(), Box<dyn std::error::Error>> {
        let anvils = create_anvil_instances(1, 8551);
        let configs = create_configs(&anvils);
        let (handle, client) =
            ChainManagerImpl::new(configs).create_start_server("127.0.0.1:3003").await?;

        let error = client
            .finalised_header(99_999, BlockNumberOrTag::Latest)
            .await
            .expect_err("expected unconfigured chain id error");

        let text = format!("{error:?}");
        assert!(text.contains("not configured") || text.contains("Chain ID"));

        handle.stop()?;
        handle.stopped().await;
        Ok(())
    }
}
