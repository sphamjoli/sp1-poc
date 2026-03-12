use crate::{bindings::Certificate, catalog::DevValidator};
use alloy::{
    primitives::{Address, Bytes, B256, U256},
    signers::{local::PrivateKeySigner, Signer},
    sol_types::SolValue,
};
use eyre::{eyre, Result};
use serde::Serialize;
use sha3::Keccak256;
use std::{
    str::FromStr,
    time::{SystemTime, UNIX_EPOCH},
};
use sylow::{G1Affine, GroupTrait, XMDExpander};

pub const STAKE_POP_DOMAIN: &str = "StakeManager:BN254:PoP:v1:";
pub const ATTESTATION_DOMAIN: &str = "ValidatorManager:BN254:Attestation:v1:";

#[derive(Debug, Clone, Serialize)]
pub struct SignedAttestation {
    pub validator: Address,
    #[serde(rename = "sourceChainId")]
    pub source_chain_id: u64,
    #[serde(rename = "blockNumber")]
    pub block_number: u64,
    #[serde(rename = "bridgeRoot")]
    pub bridge_root: B256,
    #[serde(rename = "stateRoot")]
    pub state_root: B256,
    pub timestamp: u64,
    pub signature: [String; 2],
}

#[derive(Debug, Clone, Serialize)]
pub struct CertificateEnvelope {
    pub validator: Address,
    #[serde(rename = "targetChainId")]
    pub target_chain_id: u64,
    #[serde(rename = "issuedAt")]
    pub issued_at: u64,
    #[serde(rename = "expiresAt")]
    pub expires_at: u64,
    #[serde(rename = "certificateHex")]
    pub certificate_hex: String,
    pub signer: Address,
}

pub fn attestation_message_bytes(
    source_chain_id: u64,
    block_number: u64,
    bridge_root: B256,
    state_root: B256,
    timestamp: u64,
    validator: Address,
) -> Vec<u8> {
    (
        U256::from(source_chain_id),
        U256::from(block_number),
        bridge_root,
        state_root,
        U256::from(timestamp),
        validator,
    )
        .abi_encode_packed()
}

pub fn stake_pop_message_bytes(
    chain_id: u64,
    bls_public_key_words: [U256; 4],
    validator: Address,
) -> Vec<u8> {
    (
        U256::from(chain_id),
        bls_public_key_words[0],
        bls_public_key_words[1],
        bls_public_key_words[2],
        bls_public_key_words[3],
        validator,
    )
        .abi_encode_packed()
}

pub fn sign_stake_pop(validator: &DevValidator, chain_id: u64) -> Result<[U256; 2]> {
    let message_bytes =
        stake_pop_message_bytes(chain_id, validator.bls_public_key_words()?, validator.address()?);
    let expander = XMDExpander::<Keccak256>::new(STAKE_POP_DOMAIN.as_bytes(), 96);
    let signature = G1Affine::sign_message(&expander, &message_bytes, validator.bls_secret_key()?)
        .map_err(|error| eyre!("failed to sign stake proof for {}: {:?}", validator.name, error))?;

    Ok(g1_to_words(&signature))
}

pub fn sign_attestation(
    validator: &DevValidator,
    source_chain_id: u64,
    block_number: u64,
    bridge_root: B256,
    state_root: B256,
    timestamp: u64,
) -> Result<SignedAttestation> {
    let validator_address = validator.address()?;
    let message_bytes = attestation_message_bytes(
        source_chain_id,
        block_number,
        bridge_root,
        state_root,
        timestamp,
        validator_address,
    );
    let expander = XMDExpander::<Keccak256>::new(ATTESTATION_DOMAIN.as_bytes(), 96);
    let signature = G1Affine::sign_message(&expander, &message_bytes, validator.bls_secret_key()?)
        .map_err(|error| eyre!("failed to sign attestation for {}: {:?}", validator.name, error))?;
    let signature_words = g1_to_words(&signature);

    Ok(SignedAttestation {
        validator: validator_address,
        source_chain_id,
        block_number,
        bridge_root,
        state_root,
        timestamp,
        signature: [
            u256_to_prefixed_hex(signature_words[0]),
            u256_to_prefixed_hex(signature_words[1]),
        ],
    })
}

pub async fn issue_certificate(
    owner_signer: &PrivateKeySigner,
    validator: Address,
    target_chain_id: u64,
    issued_at: u64,
    expires_at: u64,
) -> Result<CertificateEnvelope> {
    let certificate_digest = alloy::primitives::keccak256(
        (validator, U256::from(issued_at), U256::from(expires_at), U256::from(target_chain_id))
            .abi_encode(),
    );
    let signature = owner_signer.sign_message(certificate_digest.as_slice()).await?;
    let certificate = Certificate {
        validator,
        issuedAt: U256::from(issued_at),
        expiresAt: U256::from(expires_at),
        chainId: U256::from(target_chain_id),
        signature: Bytes::from(signature.as_bytes().to_vec()),
    };

    Ok(CertificateEnvelope {
        validator,
        target_chain_id,
        issued_at,
        expires_at,
        certificate_hex: format!("0x{}", hex::encode(certificate.abi_encode())),
        signer: owner_signer.address(),
    })
}

pub fn parse_hex_bytes_32(value: &str) -> Result<[u8; 32]> {
    let trimmed_value = value.trim_start_matches("0x");
    let decoded_bytes = hex::decode(trimmed_value)?;
    if decoded_bytes.len() != 32 {
        return Err(eyre!("expected 32-byte hex value, got {} bytes", decoded_bytes.len()));
    }

    let mut result = [0u8; 32];
    result.copy_from_slice(&decoded_bytes);
    Ok(result)
}

pub fn parse_u256_hex(value: &str) -> Result<U256> {
    U256::from_str(value).map_err(|error| eyre!("invalid U256 value {value}: {error}"))
}

pub fn parse_u256_hex_or_decimal(value: &str) -> Result<U256> {
    U256::from_str(value).map_err(|error| eyre!("invalid U256 value {value}: {error}"))
}

pub fn unix_timestamp() -> Result<u64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs())
}

fn g1_to_words(point: &G1Affine) -> [U256; 2] {
    let bytes = point.to_be_bytes();
    [U256::from_be_slice(&bytes[0..32]), U256::from_be_slice(&bytes[32..64])]
}

pub fn u256_to_prefixed_hex(value: U256) -> String {
    format!("0x{}", hex::encode(value.to_be_bytes::<32>()))
}

#[cfg(test)]
mod tests {
    use super::{
        attestation_message_bytes, parse_hex_bytes_32, sign_stake_pop, stake_pop_message_bytes,
    };
    use crate::ValidatorCatalog;
    use alloy::primitives::{address, b256};

    #[test]
    fn attestation_message_encoding_matches_expected_layout() {
        let encoded_message = attestation_message_bytes(
            8453,
            42,
            b256!("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            b256!("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
            1_700_000_000,
            address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"),
        );

        assert_eq!(encoded_message.len(), 180);
        assert_eq!(
            &hex::encode(&encoded_message[..32]),
            "0000000000000000000000000000000000000000000000000000000000002105"
        );
        assert_eq!(
            &hex::encode(&encoded_message[32..64]),
            "000000000000000000000000000000000000000000000000000000000000002a"
        );
    }

    #[test]
    fn parse_hex_bytes_requires_exact_length() {
        let result = parse_hex_bytes_32("0x1234");
        assert!(result.is_err());
    }

    #[test]
    fn stake_pop_message_encoding_matches_expected_layout() {
        let encoded_message = stake_pop_message_bytes(
            8453,
            [
                alloy::primitives::U256::from(1_u64),
                alloy::primitives::U256::from(2_u64),
                alloy::primitives::U256::from(3_u64),
                alloy::primitives::U256::from(4_u64),
            ],
            address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"),
        );

        assert_eq!(encoded_message.len(), 180);
        assert_eq!(
            &hex::encode(&encoded_message[..32]),
            "0000000000000000000000000000000000000000000000000000000000002105"
        );
    }

    #[test]
    fn derived_stake_pop_matches_checked_in_vector() {
        let workspace_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let validator_catalog =
            ValidatorCatalog::load(&workspace_root.join("config/dev-validators.json"))
                .expect("validator catalog should load");
        let validator = validator_catalog.by_name("alice").expect("alice should exist");

        let derived_signature = sign_stake_pop(validator, 8453).expect("stake proof should sign");

        assert_eq!(
            [
                super::u256_to_prefixed_hex(derived_signature[0]),
                super::u256_to_prefixed_hex(derived_signature[1]),
            ],
            validator
                .stake_pop_signature_by_chain
                .get("8453")
                .cloned()
                .expect("legacy vector should exist"),
        );
    }
}
