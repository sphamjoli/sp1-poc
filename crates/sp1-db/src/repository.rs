use crate::utils::{ATTESTATION_QUERY_ALL, CLAIM_QUERY_ALL, DEPOSIT_QUERY_ALL};

use alloy_primitives::{Address, Bytes, B256, U256};
use alloy_sol_types::sol;
use bloomfilter::Bloom;
use gql_client::Client;
use mongodb::sync::Collection;
use std::{collections::HashMap, convert::TryFrom};

sol! {
    pragma solidity ^0.8.30;

    interface IBridge {
        event Deposit(
            address indexed who,
            uint256 amount,
            address indexed token,
            address to,
            uint256 sourceChain,
            uint256 destinationChain,
            uint256 depositIndex,
            bytes32 indexed depositRoot
        );

        event Claimed(
            address indexed claimer,
            uint256 indexed amount,
            address indexed token,
            address recipient,
            uint256 sourceChain,
            uint256 depositIndex,
            uint256 claimIndex,
            bytes32 sourceRoot,
            bytes32 claimRoot,
            uint256 destinationChain
        );

        struct BridgeAttestation {
            uint256 blockNumber;
            bytes32 bridgeRoot;
            bytes32 stateRoot;
            uint256 sourceChainId;
            uint256 timestamp;
            address validator;
            bytes certificate;
            uint256[2] signature;
        }

        struct SlashParams {
            address validator;
            uint256 slashAmount;
        }

        struct VerificationPublicValues {
            uint256 attestedChainId;
            BridgeAttestation[] attestations;
            SlashParams[] equivocators;
            bytes32 validBridgeRoot;
        }

        struct VerificationParams {
            bytes publicValues;
            bytes proofBytes;
        }
    }
}

/// Row shape coming from Hasura for AttestationSubmitted.
/// Keep this as strings and parse into `IBridge::BridgeAttestation` when building the proof input.
#[derive(Default, Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct BridgeAttestationEvent {
    #[serde(rename = "sourceBlockNumber")]
    pub block_number: String,
    #[serde(rename = "bridgeRoot")]
    pub bridge_root: String,
    #[serde(rename = "stateRoot")]
    pub state_root: String,
    #[serde(rename = "sourceChainId")]
    pub source_chain_id: String,
    pub timestamp: String,
    pub validator: String,
    #[serde(rename = "validatorManager", default)]
    pub validator_manager: String,
    #[serde(rename = "transactionHash", default)]
    pub transaction_hash: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct AttestationResponse {
    #[serde(rename = "Attestation")]
    attestations: Vec<BridgeAttestationEvent>,
}

#[derive(Default, Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct BridgeEvent {
    pub who: String,
    pub amount: String,
    pub token: String,
    pub id: String,
    pub gas_used: String,
    pub timestamp: String,
    pub transaction_hash: String,
    pub source_chain: String,
    pub destination_chain: String,
    pub to: String,
    pub block_number: String,
    /// bytes32 hex (0x-prefixed) from the Deposit log topic
    pub deposit_root: String,
    /// decimal string of the deposit index
    pub deposit_index: String,
}

#[derive(Default, Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BridgeConfig {
    pub claim_tree: String,
    pub chain_id: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
pub struct ClaimEvent {
    pub who: String,
    pub amount: String,
    pub token: String,
    pub id: String,
    pub gas_used: String,
    pub timestamp: String,
    pub transaction_hash: String,
    pub source_chain: Option<String>,
    pub destination_chain: String,
    pub to: String,
    pub proof_bytes: String,
    pub public_inputs: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct DepositResponse {
    #[serde(rename = "Deposit")]
    deposits: Vec<DepositData>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CreatedProof {
    pub event_hash: String,
    pub chain_id: u64,
    pub proof: String,
    pub public_values: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClaimResponse {
    #[serde(rename = "Claim")]
    claims: Vec<ClaimData>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct DepositData {
    id: String,
    #[serde(rename = "gasUsed", default)]
    gas_used: Option<String>,
    to: String,
    amount: String,
    timestamp: String,
    #[serde(rename = "transactionHash")]
    transaction_hash: String,
    #[serde(rename = "sourceChain")]
    source_chain: String,
    #[serde(rename = "destinationChain")]
    destination_chain: String,
    #[serde(rename = "depositIndex", default)]
    deposit_index: String,
    #[serde(rename = "depositRoot", default)]
    deposit_root: String,
    #[serde(rename = "blockNumber", default)]
    block_number: String,
    #[serde(default)]
    who: String,
    #[serde(rename = "user_id", default)]
    user_id: String,
    #[serde(rename = "token_id", default)]
    token_id: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct ClaimData {
    id: String,
    #[serde(rename = "gasUsed", default)]
    gas_used: Option<String>,
    claimer: String,
    amount: String,
    timestamp: String,
    #[serde(rename = "transactionHash")]
    transaction_hash: String,
    #[serde(rename = "sourceChain")]
    source_chain: String,
    #[serde(rename = "destinationChain")]
    destination_chain: String,
    #[serde(rename = "proofBytes")]
    proof_bytes: String,
    #[serde(rename = "publicInputs")]
    public_inputs: String,
    #[serde(rename = "recipient")]
    recipient: String,
    #[serde(rename = "depositIndex")]
    deposit_index: String,
    #[serde(rename = "sourceRoot")]
    source_root: String,
    #[serde(rename = "claimRoot")]
    claim_root: String,
    #[serde(rename = "claimIndex")]
    claim_index: String,
    user_id: String,
    token_id: String,
}

pub trait EventRepository {
    fn get_deposit_events(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<BridgeEvent>, Box<dyn std::error::Error>>;

    fn get_claim_events(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<ClaimEvent>, Box<dyn std::error::Error>>;

    fn get_submitted_attestations(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<IBridge::BridgeAttestation>, Box<dyn std::error::Error>>;

    fn get_deposits_by_user(&self, user_address: &str) -> Vec<&BridgeEvent>;
    fn get_claims_by_user(&self, user_address: &str) -> Vec<&ClaimEvent>;
    fn get_unverified_deposits(&self) -> Vec<&BridgeEvent>;
}

pub trait StateRepository {
    fn get_bridge_config(
        &mut self,
        chain_id: u64,
    ) -> Result<Option<BridgeConfig>, Box<dyn std::error::Error>>;

    fn store_bridge_config(&self, config: BridgeConfig) -> Result<(), Box<dyn std::error::Error>>;

    fn get_created_proofs(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<CreatedProof>, Box<dyn std::error::Error>>;

    fn update_bridge_config(
        &self,
        chain_id: u64,
        config: BridgeConfig,
    ) -> Result<(), Box<dyn std::error::Error>>;

    fn get_processed_events(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<ClaimEvent>, Box<dyn std::error::Error>>;

    fn store_processed_claim(
        &mut self,
        event: ClaimEvent,
    ) -> Result<(), Box<dyn std::error::Error>>;
}

#[derive(Debug)]
pub struct BridgeRepository {
    pub client: Client,
    pub deposit_events: Vec<BridgeEvent>,
    pub claim_events: Vec<ClaimEvent>,
    pub attestation_events: Vec<BridgeAttestationEvent>,
}

#[derive(Debug)]
pub struct MongoDBRepository {
    pub db_collection: Collection<ClaimEvent>,
    pub bridge_config_collection: Collection<BridgeConfig>,
    pub processed_claims: Vec<ClaimEvent>,
    pub bridge_configs: HashMap<u64, BridgeConfig>,
    pub proof_collection: Collection<CreatedProof>,
    pub bloom: Bloom<[u8; 32]>,
}

impl BridgeRepository {
    pub fn new(
        endpoint: String,
        hasura_secret: String,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let mut headers: HashMap<String, _> = HashMap::default();
        headers.insert("x-hasura-admin-secret".into(), hasura_secret);
        let client = Client::new_with_headers(&endpoint, headers);
        Ok(Self {
            client,
            deposit_events: Vec::new(),
            claim_events: Vec::new(),
            attestation_events: Vec::new(),
        })
    }

    async fn fetch_deposits_async(&self) -> Result<Vec<BridgeEvent>, Box<dyn std::error::Error>> {
        let response = match self.client.query::<DepositResponse>(&DEPOSIT_QUERY_ALL).await {
            Ok(Some(response)) => response,
            Ok(None) => return Err("No response from query".into()),
            Err(error) => return Err(format!("{:?}", error.message().to_owned()).into()),
        };

        Ok(response
            .deposits
            .into_iter()
            .map(|e| BridgeEvent {
                who: e.who,
                amount: e.amount,
                token: e.token_id,
                id: e.id,
                gas_used: e.gas_used.unwrap_or_default(),
                timestamp: e.timestamp,
                transaction_hash: e.transaction_hash,
                source_chain: e.source_chain,
                destination_chain: e.destination_chain,
                to: e.to,
                block_number: e.block_number,
                deposit_root: e.deposit_root,
                deposit_index: e.deposit_index,
            })
            .collect())
    }

    async fn fetch_claims_async(&self) -> Result<Vec<ClaimEvent>, Box<dyn std::error::Error>> {
        let response = match self.client.query::<ClaimResponse>(&CLAIM_QUERY_ALL).await {
            Ok(Some(response)) => response,
            Ok(None) => return Err("No response from query".into()),
            Err(error) => return Err(format!("{:?}", error.message().to_owned()).into()),
        };

        Ok(response
            .claims
            .into_iter()
            .map(|e| ClaimEvent {
                who: e.user_id,
                amount: e.amount,
                token: e.token_id,
                id: e.id,
                gas_used: e.gas_used.unwrap_or_default(),
                timestamp: e.timestamp,
                transaction_hash: e.transaction_hash,
                source_chain: Some(e.source_chain),
                destination_chain: e.destination_chain,
                to: e.recipient,
                proof_bytes: e.proof_bytes,
                public_inputs: e.public_inputs,
            })
            .collect())
    }

    async fn fetch_attestations_async(
        &self,
    ) -> Result<Vec<BridgeAttestationEvent>, Box<dyn std::error::Error>> {
        let response = match self.client.query::<AttestationResponse>(&ATTESTATION_QUERY_ALL).await
        {
            Ok(Some(response)) => response,
            Ok(None) => return Err("No response from query".into()),
            Err(error) => return Err(format!("{:?}", error.message().to_owned()).into()),
        };

        Ok(response.attestations)
    }
}

fn parse_b256(value: &str) -> Result<B256, Box<dyn std::error::Error>> {
    Ok(value.parse::<B256>()?)
}

fn parse_address(value: &str) -> Result<Address, Box<dyn std::error::Error>> {
    Ok(value.parse::<Address>()?)
}

fn parse_u64(value: &str) -> Result<u64, Box<dyn std::error::Error>> {
    let trimmed = value.trim();
    let hex = trimmed.strip_prefix("0x").or_else(|| trimmed.strip_prefix("0X"));
    if let Some(h) = hex {
        Ok(u64::from_str_radix(h, 16)?)
    } else {
        Ok(trimmed.parse::<u64>()?)
    }
}

fn attestation_event_to_sol(
    e: &BridgeAttestationEvent,
) -> Result<IBridge::BridgeAttestation, Box<dyn std::error::Error>> {
    Ok(IBridge::BridgeAttestation {
        blockNumber: U256::from(parse_u64(&e.block_number)?),
        bridgeRoot: parse_b256(&e.bridge_root)?,
        stateRoot: parse_b256(&e.state_root)?,
        sourceChainId: U256::from(parse_u64(&e.source_chain_id)?),
        timestamp: U256::from(parse_u64(&e.timestamp)?),
        validator: parse_address(&e.validator)?,
        certificate: Bytes::new(),
        signature: [U256::ZERO, U256::ZERO],
    })
}

impl EventRepository for BridgeRepository {
    fn get_deposit_events(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<BridgeEvent>, Box<dyn std::error::Error>> {
        let rt = tokio::runtime::Runtime::new()?;
        self.deposit_events = rt.block_on(self.fetch_deposits_async())?;

        Ok(self
            .deposit_events
            .iter()
            .filter(|e| parse_u64(&e.source_chain).map(|v| v == chain_id).unwrap_or(false))
            .cloned()
            .collect())
    }

    fn get_claim_events(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<ClaimEvent>, Box<dyn std::error::Error>> {
        let rt = tokio::runtime::Runtime::new()?;
        self.claim_events = rt.block_on(self.fetch_claims_async())?;

        Ok(self
            .claim_events
            .iter()
            .filter(|e| parse_u64(&e.destination_chain).map(|v| v == chain_id).unwrap_or(false))
            .cloned()
            .collect())
    }

    fn get_submitted_attestations(
        &mut self,
        chain_id: u64,
    ) -> Result<Vec<IBridge::BridgeAttestation>, Box<dyn std::error::Error>> {
        let rt = tokio::runtime::Runtime::new()?;
        self.attestation_events = rt.block_on(self.fetch_attestations_async())?;

        let mut out = Vec::new();
        for event in &self.attestation_events {
            let attestation = attestation_event_to_sol(event)?;
            let source_chain_id = u64::try_from(attestation.sourceChainId)
                .map_err(|_| "attestation sourceChainId does not fit into u64")?;

            if source_chain_id == chain_id {
                out.push(attestation);
            }
        }

        Ok(out)
    }

    fn get_deposits_by_user(&self, user: &str) -> Vec<&BridgeEvent> {
        self.deposit_events.iter().filter(|e| e.who == user).collect()
    }

    fn get_claims_by_user(&self, user: &str) -> Vec<&ClaimEvent> {
        self.claim_events.iter().filter(|e| e.who == user).collect()
    }

    fn get_unverified_deposits(&self) -> Vec<&BridgeEvent> {
        self.deposit_events
            .iter()
            .filter(|d| {
                !self
                    .claim_events
                    .iter()
                    .any(|c| c.who == d.who && c.amount == d.amount && c.token == d.token)
            })
            .collect()
    }
}

impl MongoDBRepository {
    pub fn new(mongodb_url: String) -> Result<Self, Box<dyn std::error::Error>> {
        let client = mongodb::sync::Client::with_uri_str(&mongodb_url)?;
        let db = client.database("bridge");
        Ok(Self {
            db_collection: db.collection("claims"),
            bridge_config_collection: db.collection("bridge_configs"),
            processed_claims: Vec::new(),
            bridge_configs: HashMap::new(),
            proof_collection: db.collection("proofs"),
            bloom: Bloom::new_for_fp_rate(10_000, 0.01).expect("bloom filter init"),
        })
    }

    /// Returns true if the tx_hash has already been processed.
    pub fn event_exists(&self, tx_hash: &str) -> bool {
        let stripped = tx_hash.strip_prefix("0x").unwrap_or(tx_hash);
        if let Ok(raw) = alloy_primitives::hex::decode(stripped) {
            if raw.len() == 32 {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&raw);
                return self.bloom.check(&arr);
            }
        }
        false
    }

    /// Mark a tx_hash as processed in the bloom filter.
    pub fn mark_event_processed(&mut self, tx_hash: &str) {
        let stripped = tx_hash.strip_prefix("0x").unwrap_or(tx_hash);
        if let Ok(raw) = alloy_primitives::hex::decode(stripped) {
            if raw.len() == 32 {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&raw);
                self.bloom.set(&arr);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy_primitives::{Address, B256};

    #[test]
    fn parse_u64_supports_decimal_and_hex() {
        assert_eq!(parse_u64("42").unwrap(), 42);
        assert_eq!(parse_u64("0x2a").unwrap(), 42);
        assert_eq!(parse_u64("0X2A").unwrap(), 42);
    }

    #[test]
    fn parse_u256_supports_decimal_and_hex() {
        assert_eq!(parse_u256("42").unwrap(), U256::from(42));
        assert_eq!(parse_u256("0x2a").unwrap(), U256::from(42));
    }

    #[test]
    fn attestation_event_maps_to_sol_struct() {
        let event = BridgeAttestationEvent {
            block_number: "100".to_string(),
            bridge_root: format!("{:#x}", B256::from([0xabu8; 32])),
            state_root: format!("{:#x}", B256::from([0xcdu8; 32])),
            source_chain_id: "8453".to_string(),
            timestamp: "1700000000".to_string(),
            validator: Address::from([0x11u8; 20]).to_string(),
            validator_manager: Address::from([0x22u8; 20]).to_string(),
            transaction_hash: format!("{:#x}", B256::from([0xeeu8; 32])),
        };

        let mapped = attestation_event_to_sol(&event).unwrap();
        assert_eq!(mapped.blockNumber, U256::from(100));
        assert_eq!(mapped.sourceChainId, U256::from(8453));
        assert_eq!(mapped.validator, Address::from([0x11u8; 20]));
        assert_eq!(mapped.signature[0], U256::ZERO);
        assert_eq!(mapped.signature[1], U256::ZERO);
    }
}
