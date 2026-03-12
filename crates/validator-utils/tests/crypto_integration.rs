use alloy::{
    primitives::{address, b256},
    sol_types::SolValue,
};
use validator_utils::{bindings::Certificate, issue_certificate, sign_attestation, LoadedRuntime};

fn runtime() -> LoadedRuntime {
    let workspace_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    LoadedRuntime::load(workspace_root.join("config/runtime.local.json"))
        .expect("runtime should load")
}

#[tokio::test]
async fn certificate_encoding_round_trips() {
    let runtime = runtime();
    let certificate = issue_certificate(
        &runtime.owner_signer().expect("owner signer"),
        address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"),
        8453,
        1_700_000_000,
        1_700_000_600,
    )
    .await
    .expect("certificate should be issued");

    let encoded_bytes = hex::decode(certificate.certificate_hex.trim_start_matches("0x"))
        .expect("hex should decode");
    let decoded_certificate =
        Certificate::abi_decode(&encoded_bytes).expect("certificate should decode");

    assert_eq!(decoded_certificate.validator, address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"));
    assert_eq!(decoded_certificate.chainId.to::<u64>(), 8453);
}

#[test]
fn attestation_signing_uses_checked_in_validator_keys() {
    let runtime = runtime();
    let signed_attestation = sign_attestation(
        runtime.validator_catalog.by_name("alice").expect("alice"),
        1,
        42,
        b256!("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        b256!("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
        1_700_000_000,
    )
    .expect("attestation should sign");

    assert_eq!(signed_attestation.validator, address!("328809Bc894f92807417D2dAD6b7C998c1aFdac6"));
    assert_eq!(signed_attestation.signature.len(), 2);
    assert!(signed_attestation.signature[0].starts_with("0x"));
    assert!(signed_attestation.signature[1].starts_with("0x"));
}
