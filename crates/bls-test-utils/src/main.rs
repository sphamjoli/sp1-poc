use std::{fs, str::FromStr};

use alloy_primitives::{Address, U256};
use alloy_sol_types::SolValue;
use serde::{Deserialize, Serialize};
use sha3::Keccak256;
use sylow::{
    pairing, Fp, G1Affine, G1Projective, G2Affine, G2Projective, GroupTrait, KeyPair, XMDExpander,
};

const DST: &str = "StakeManager:BN254:PoP:v1:";

#[derive(Serialize, Deserialize)]
struct BlsTestData {
    private_key: String,
    public_key: [String; 4],
    proof_of_possession: [String; 2],
    wallet_address: String,
    domain: String,
    message_hash: [String; 2],
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

fn generate_single_case(wallet_address: &str) -> BlsTestData {
    let kp: KeyPair = KeyPair::generate();

    let pk_affine: G2Affine = G2Affine::from(kp.public_key);
    let pk_words = g2_to_words_solidity(&pk_affine);

    // abi.encodePacked(pk limbs, msg.sender)
    let sender = Address::from_str(wallet_address).expect("address");
    let message_bytes =
        (pk_words[0], pk_words[1], pk_words[2], pk_words[3], sender).abi_encode_packed();

    let exp = XMDExpander::<Keccak256>::new(DST.as_bytes(), 96);

    // H2C and PoP signature
    let h: G1Affine = G1Affine::hash_to_curve(&exp, &message_bytes).expect("h2c");
    let msg_xy = g1_to_words(&h);

    let sig: G1Affine = G1Affine::sign_message(&exp, &message_bytes, kp.secret_key).expect("sign");
    let sig_xy = g1_to_words(&sig);

    // Local pairing check
    let lhs = pairing(&G1Projective::from(sig), &G2Projective::from(G2Affine::generator()));
    let rhs = pairing(&G1Projective::from(h), &G2Projective::from(pk_affine));
    if lhs != rhs {
        eprintln!("WARNING: pairing check failed for {}", wallet_address);
    }

    BlsTestData {
        private_key: fp_to_hex(kp.secret_key),
        public_key: [
            u256_to_0x(pk_words[0]),
            u256_to_0x(pk_words[1]),
            u256_to_0x(pk_words[2]),
            u256_to_0x(pk_words[3]),
        ],
        proof_of_possession: [u256_to_0x(sig_xy[0]), u256_to_0x(sig_xy[1])],
        wallet_address: wallet_address.to_string(),
        domain: DST.to_string(),
        message_hash: [u256_to_0x(msg_xy[0]), u256_to_0x(msg_xy[1])],
    }
}

fn verify_g2_generator() {
    let g2_gen = G2Affine::generator();
    let g2_bytes = g2_gen.to_be_bytes();

    println!("Sylow G2 generator (c0=imag, c1=real):");
    println!("  x.c0 (im): {}", U256::from_be_slice(&g2_bytes[0..32]));
    println!("  x.c1 (re): {}", U256::from_be_slice(&g2_bytes[32..64]));
    println!("  y.c0 (im): {}", U256::from_be_slice(&g2_bytes[64..96]));
    println!("  y.c1 (re): {}", U256::from_be_slice(&g2_bytes[96..128]));
}

fn main() {
    let wallets = [
        "0x328809Bc894f92807417D2dAD6b7C998c1aFdac6",
        "0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e",
        "0xcDFdF57D10EA95520a2CF09119Db2d2afa6F6bf7",
        "0x52d4630789F63F9C715a2D30fCe65727D009f8d9",
        "0x7c8999dC9a822c1f0Df42023113EDB4FDd543266",
    ];

    let mut out = Vec::with_capacity(wallets.len());
    for w in wallets {
        out.push(generate_single_case(w));
    }
    verify_g2_generator();
    fs::write("bls_test_data.json", serde_json::to_string_pretty(&out).unwrap()).expect("write");
}
