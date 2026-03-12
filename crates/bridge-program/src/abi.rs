extern crate alloc;
use alloc::vec::Vec;
use alloy_primitives::{B256, U256};
use alloy_sol_types::{sol, SolValue};

sol! {
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
}

pub fn encode_public_values(
    attested_chain_id: u64,
    valid_bridge_root: B256,
    attestations: Vec<BridgeAttestation>,
    equivocators: Vec<SlashParams>,
) -> Vec<u8> {
    let public_values = VerificationPublicValues {
        attestedChainId: U256::from(attested_chain_id),
        attestations,
        equivocators,
        validBridgeRoot: valid_bridge_root.0.into(),
    };
    public_values.abi_encode()
}
