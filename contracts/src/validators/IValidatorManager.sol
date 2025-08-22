// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

///
/// @title IValidatorManager
/// @author Brianspha
/// @notice Core validator management interface for bridge state verification
///
/// OVERVIEW:
/// This system enables decentralized validation of cross-chain bridge states through
/// economic incentives and cryptographic verification. Validators stake tokens to
/// participate in submitting bridge contract state roots, which are then verified
/// off-chain using SP1 zero-knowledge proofs which generate Groth16 Proofs for
/// onchain verification.
///
/// VALIDATOR LIFECYCLE:
/// 1. Stake minimum tokens to become validator
/// 2. Submit BLS-signed attestations of bridge contract roots
/// 3. Earn rewards for honest participation
/// 4. Face slashing for malicious/incorrect submissions
///
/// CONSENSUS MECHANISM:
/// - Validators monitor bridge contracts across supported chains
/// - Submit signed attestations of (chainId, blockNumber, bridgeRoot, stateRoot)
/// - Off-chain SP1 prover verifies submitted roots against actual chain state
/// - Only cryptographically verified roots are accepted for bridge claims
///
/// ECONOMIC SECURITY:
/// - Minimum stake requirement prevents spam
/// - Slashing penalty deters malicious behavior
/// - Reward distribution incentivizes honest participation
/// - Gradual unstaking prevents sudden validator exits
///
import {IValidatorTypes} from "./IValidatorTypes.sol";

interface IValidatorManager is IValidatorTypes {
    /// @notice Initialize the ValidatorManager contract
    /// @param owner Initial owner of the contract
    function initialize(address owner) external;

    /// @notice Submit bridge state root attestation
    /// @param attestation Signed attestation of bridge state - see {IValidatorTypes.BridgeAttestation}
    /// @dev Validator must be active and signature must be valid
    function submitAttestation(BridgeAttestation calldata attestation) external;

    /// @notice Submit multiple attestations in a single transaction
    /// @param attestations Array of signed bridge attestations - see {IValidatorTypes.BridgeAttestation}
    /// @dev More gas efficient for validators monitoring multiple chains
    function submitBatchAttestations(BridgeAttestation[] calldata attestations) external;

    /// @notice used to set all validators who supplied correct attestions
    /// @param attestations Array of signed bridge attestations - see {IValidatorTypes.BridgeAttestation}
    /// @dev This is called after the SP1 prover completes validating bridge roots
    function finaliseAttestations(BridgeAttestation[] calldata attestations) external;

    /// @notice Check if bridge root has been verified by SP1 system
    /// @param params Root verification parameters - see {IValidatorTypes.RootParams}
    /// @return verified True if root has passed SP1 verification
    function isRootVerified(RootParams calldata params) external view returns (bool verified);

    /// @notice Get validator information
    /// @param validator Validator address
    /// @return info Complete validator information struct - see {IValidatorTypes.ValidatorInfo}
    function getValidator(address validator) external view returns (ValidatorInfo memory info);

    /// @notice Get all active validators
    /// @return validators Array of active validator addresses
    function getActiveValidators() external view returns (address[] memory validators);

    /// @notice Get aggregated BLS public key for signature verification
    /// @param validators Array of validator addresses
    /// @return aggregatedKey Combined BLS public key for signature verification
    function getAggregatedPublicKey(address[] calldata validators) external view returns (bytes memory aggregatedKey);
}
