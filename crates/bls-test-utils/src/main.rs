use alloy::{
    primitives::{Address, U256},
    sol_types::SolValue,
};
use serde::{Deserialize, Serialize};
use sha3::Keccak256;
use std::{fs, str::FromStr};
use sylow::{Fp, G1Affine, G2Affine, GroupTrait, KeyPair, XMDExpander};

const DST: &str = "StakeManager:BN254:PoP:v1:";
const DST_VALIDATOR_MANAGER: &str = "ValidatorManager:BN254:PoP:v1:";

#[derive(Serialize, Deserialize)]
struct ProofData {
    message_hash_stake_manager: [String; 2],
    message_hash_validator_manager: [String; 2],
    proof_of_possession_stake_manager: [String; 2],
    proof_of_possession_validator_manager: [String; 2],
    chain_id: String,
}

#[derive(Serialize, Deserialize)]
struct BlsTestData {
    private_key: String,
    public_key: [String; 4],
    wallet_address: String,
    domain_staking_manager: String,
    domain_validator_manager: String,
    proof: Vec<ProofData>,
}

fn u256_to_0x(x: U256) -> String {
    format!("0x{}", hex::encode(x.to_be_bytes::<32>()))
}

fn fp_to_hex(x: Fp) -> String {
    format!("0x{}", hex::encode(x.to_be_bytes()))
}

fn g1_to_words(p: &G1Affine) -> [U256; 2] {
    let b = p.to_be_bytes();
    [U256::from_be_slice(&b[0..32]), U256::from_be_slice(&b[32..64])]
}

/// Return limbs in Solidity order: [x_re, x_im, y_re, y_im].
/// Sylow bytes are [x.c0, x.c1, y.c0, y.c1] with c0=imag, c1=real.
fn g2_to_words_solidity(p: &G2Affine) -> [U256; 4] {
    let b = p.to_be_bytes();
    let x_im = U256::from_be_slice(&b[0..32]);
    let x_re = U256::from_be_slice(&b[32..64]);
    let y_im = U256::from_be_slice(&b[64..96]);
    let y_re = U256::from_be_slice(&b[96..128]);
    [x_re, x_im, y_re, y_im]
}

fn generate_single_case(wallet_address: &str, chain_ids: &[U256]) -> BlsTestData {
    let kp: KeyPair = KeyPair::generate();

    let pk_affine: G2Affine = G2Affine::from(kp.public_key);
    let pk_words = g2_to_words_solidity(&pk_affine);

    let sender = Address::from_str(wallet_address).expect("address");
    let mut proof_data: Vec<ProofData> = Vec::new();

    for chain_id in chain_ids {
        let message_bytes = (chain_id, pk_words[0], pk_words[1], pk_words[2], pk_words[3], sender)
            .abi_encode_packed();

        let expander_stake_manager = XMDExpander::<Keccak256>::new(DST.as_bytes(), 96);
        let expander_validator_manager =
            XMDExpander::<Keccak256>::new(DST_VALIDATOR_MANAGER.as_bytes(), 96);

        // H2C and PoP signature
        let curve_stake_manager: G1Affine =
            G1Affine::hash_to_curve(&expander_stake_manager, &message_bytes)
                .expect("Unable to create has from curve");
        let curve_validator_manager: G1Affine =
            G1Affine::hash_to_curve(&expander_validator_manager, &message_bytes)
                .expect("Unable to create has from curve");
        let msg_xy_stake_manager = g1_to_words(&curve_stake_manager);
        let msg_xy_validator_manager = g1_to_words(&curve_validator_manager);

        let signature_stake_manager: G1Affine =
            G1Affine::sign_message(&expander_stake_manager, &message_bytes, kp.secret_key.clone())
                .expect("Unable to sign message");
        let signature_validator_manager: G1Affine =
            G1Affine::sign_message(&expander_validator_manager, &message_bytes, kp.secret_key)
                .expect("Unable to sign message");

        let sig_xy_stake_manager = g1_to_words(&signature_stake_manager);
        let sig_xy_validator_manager = g1_to_words(&signature_validator_manager);
        proof_data.push(ProofData {
            chain_id: (*chain_id).to_string(),
            proof_of_possession_stake_manager: [
                u256_to_0x(sig_xy_stake_manager[0]),
                u256_to_0x(sig_xy_stake_manager[1]),
            ],
            proof_of_possession_validator_manager: [
                u256_to_0x(sig_xy_validator_manager[0]),
                u256_to_0x(sig_xy_validator_manager[1]),
            ],
            message_hash_stake_manager: [
                u256_to_0x(msg_xy_stake_manager[0]),
                u256_to_0x(msg_xy_stake_manager[1]),
            ],
            message_hash_validator_manager: [
                u256_to_0x(msg_xy_validator_manager[0]),
                u256_to_0x(msg_xy_validator_manager[1]),
            ],
        });
    }

    /*  // Local pairing check
    let lhs = pairing(&G1Projective::from(sig), &G2Projective::from(G2Affine::generator()));
    let rhs = pairing(&G1Projective::from(h), &G2Projective::from(pk_affine));
    if lhs != rhs {
        eprintln!("WARNING: pairing check failed for {}", wallet_address);
    } */

    BlsTestData {
        private_key: fp_to_hex(kp.secret_key),
        public_key: [
            u256_to_0x(pk_words[0]),
            u256_to_0x(pk_words[1]),
            u256_to_0x(pk_words[2]),
            u256_to_0x(pk_words[3]),
        ],
        proof: proof_data,
        wallet_address: wallet_address.to_string(),
        domain_staking_manager: DST.to_string(),
        domain_validator_manager: DST_VALIDATOR_MANAGER.to_string(),
    }
}

fn main() {
    let wallets = [
        "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
        "0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e",
        "0xcDFdF57D10EA95520a2CF09119Db2d2afa6F6bf7",
        "0x52d4630789F63F9C715a2D30fCe65727D009f8d9",
        "0x5898751917a8482c6FEb4D20b6e6C7442716Fd96",
    ];
    let chain_ids = &[U256::from(8453), U256::from(1)];
    let mut out = Vec::with_capacity(wallets.len());
    for wallet in wallets {
        out.push(generate_single_case(wallet, chain_ids));
    }
    fs::write(format!("bls_test_data.json"), serde_json::to_string_pretty(&out).unwrap())
        .expect("write");
}
