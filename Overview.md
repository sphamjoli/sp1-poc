# Bridge Architecture Overview POC (WIP)

## System Purpose

This bridge system enables trustless cross-chain asset transfers through a co-processor architecture that cryptographically verifies bridge contract states across multiple networks. The system implements a pessimistic proof model using Succinct Labs' SP1 zero-knowledge virtual machine to generate mathematical guarantees of state validity, eliminating trust assumptions beyond cryptographic primitives.

## Co-processor Architecture Foundation

The bridge operates as a zero-knowledge co-processor system, extending the computational capabilities of destination networks to verify states from source networks. Traditional bridges require destination networks to trust external validators or rely on optimistic assumptions. This co-processor approach enables destination networks to cryptographically verify source network states through zero-knowledge proofs, effectively making cross-chain state verification a native computational capability.

The co-processor model separates state verification from state execution. Source networks execute transactions and maintain state, while the SP1 co-processor verifies these states and generates proofs that destination networks can efficiently validate. This separation enables networks with different consensus mechanisms and trust assumptions to interoperate securely.

## Core Architecture Components

### Unified Bridge State Management

Each network maintains a bridge contract containing a Sparse Merkle Tree that tracks all cross-chain operations. The bridge state consists of two primary components:

**Deposit Tree**: Contains all outbound transfers from the network. Each deposit creates a leaf containing the deposit parameters (amount, token, recipient, destination network). The deposit tree root represents the cumulative state of all outbound transfers and serves as the cryptographic commitment to the network's bridge obligations.

**Claim Tree**: Contains all inbound transfers claimed on the network. Each successful claim adds a leaf containing the source deposit index, originating network, and claim metadata. The claim tree root provides a cryptographic record of all assets that have been withdrawn from the bridge on this network.

These trees enable the pessimistic proof system to perform comprehensive accounting across all connected networks, ensuring no network can withdraw more assets than it has legitimately received.

### Off-Chain Proof Batching Strategy

Individual deposits are processed immediately by bridge contracts, each producing a new bridge root. The SP1 verification system operates independently by monitoring on-chain attestation events and batching proof generation off-chain to optimize computational costs. This architecture separates transaction processing from cryptographic verification without introducing on-chain queue complexity.

The off-chain batching mechanism collects attestation events over defined time intervals (typically every 5-10 minutes) and generates comprehensive proofs covering all attestations within each batch. This approach captures the economic benefits of batched proof generation while maintaining immediate on-chain processing and eliminating gas costs associated with queue management.

Economic considerations drive optimal batch sizing for proof generation. Larger proof batches reduce amortized verification costs but may increase overall proof generation latency. The SP1 system dynamically adjusts batch sizes based on attestation volume and computational load, maximizing throughput while maintaining acceptable verification performance.

### Two-Phase Verification System

The bridge implements a two-phase verification model that enables instant claims while maintaining cryptographic security through asynchronous proof generation.

**Immediate Pre-confirmation**: Validators query block headers from network nodes and submit attestations that are processed immediately upon submission. When sufficient validator attestations are collected for a specific bridge root, the pre-confirmation status is updated in real-time through event-driven processing. This allows destination networks to process claims immediately based on validator consensus, providing instant user experience without processing delays.

**Asynchronous Verification**: While users experience instant claims through immediate pre-confirmation, the SP1 system monitors attestation events and generates cryptographic proofs off-chain. These proofs mathematically verify that pre-confirmed bridge roots correctly represent actual network states. The verification process operates on batched attestations collected over time intervals, providing final cryptographic settlement.

### Chain Reorganisation Handling

Networks may experience chain reorganisations that invalidate previously observed bridge roots. The system addresses this through multiple defensive mechanisms that ensure security under reorganisation scenarios.

Validators monitor networks through multiple confirmation thresholds based on each network's reorganisation probability. Ethereum requires 12 confirmations, Polygon requires 1 confirmation, and other networks follow their respective finality rules. This approach ensures attestations reference only finalized state.

Pre-confirmation status can be revoked through immediate event processing if subsequent block headers indicate a reorganisation has invalidated the attested bridge root. The system tracks competing chains and invalidates pre-confirmations when reorganisations exceed the confirmation threshold used for attestation submission.

SP1 verification provides the ultimate defence against reorganisations by verifying all attestations against canonical network state. The SP1 system queries multiple RPC endpoints and uses the longest valid chain to ensure verification occurs against finalized state only.

### Pessimistic Proof Generation System

The pessimistic proof system assumes all networks could behave maliciously and verifies every state transition cryptographically. Using Succinct Labs' SP1 zero-knowledge virtual machine, the system generates proofs that submitted bridge roots correctly represent actual network states.

**SP1 Implementation**: Succinct Labs' SP1 provides a general-purpose zero-knowledge virtual machine that executes Rust programmes and generates proofs of correct execution. The bridge verification logic runs as a Rust programme within SP1, enabling complex state verification across different network architectures without requiring custom circuit development.

**Groth16 Compression**: Succinct Labs' SP1 virtual machine operating in Groth16 prover mode generates SNARK proofs approximately 260 bytes in size that can be verified on-chain for around 270,000 gas. This is the recommended approach for generating proofs that require efficient on-chain verification. The trusted setup for the Groth16 circuit keys relies on Succinct Labs' established trusted setup ceremony. The bridge SP1-Prover operates under the assumption that this existing trusted setup is trustworthy and secure.

### Decentralised Validator Network

Validators operate as decentralised state attestors who monitor bridge contracts across supported networks and submit cryptographic attestations of observed states. The validator network provides redundancy and liveness guarantees for pre-confirmation while the SP1 system provides ultimate correctness guarantees.

**Event Processing Architecture**: Validators receive deposit events through the centralised event indexing infrastructure while independently verifying event authenticity through direct block header queries. This dual approach provides efficient event delivery through the indexer while maintaining cryptographic verification through direct network access.

**Economic Security Model**: Validators stake tokens to participate in state attestation, creating economic alignment through slashing risk for incorrect submissions. The minimum stake requirement prevents spam while ensuring validators have economic incentive to maintain infrastructure and submit accurate attestations.

**BLS Signature Aggregation**: Validators use BLS signatures to attest to observed bridge states. The system supports both individual and aggregated signature submission methods. When multiple validators observe the same bridge root (common during stable periods), they coordinate off-chain to create aggregated signatures that can be verified with constant computational cost regardless of participant count. This dual approach provides gas efficiency when validators agree while maintaining flexibility when validators have legitimately different views of chain state.

**Attestation Structure**: The system supports two attestation formats. Individual attestations contain the network identifier, block number, bridge root, network state root, timestamp, validator address, and individual BLS signature. Aggregated attestations contain the same state data with an array of participating validator addresses and a single aggregated BLS signature representing all participants. This flexibility accommodates both scenarios where validators agree (enabling gas optimization) and where they have different but legitimate views of bridge state.

## Technical Operation Flow

### Deposit Execution Process

When users initiate cross-chain transfers, the source network's bridge contract processes each deposit individually. Each deposit is added to the local Sparse Merkle Tree, and a Deposit event is emitted. Every Deposit event includes the updated bridge root representing the cumulative state of all deposits (including the current transaction), the deposit index, and relevant transaction metadata.

Because deposits are processed individually rather than in batches, each transaction produces a new bridge root that validators must attest to. This approach provides immediate transaction finality while enabling efficient downstream processing.

Validators receive these Deposit events via a centralised event indexer, which ensures efficient delivery and preserves the correct ordering across networks. Validators must independently verify event authenticity by querying block headers from the network nodes. For each event, the verification involves two steps: confirming the transaction hash producing the event is included in the block's transactions root, and confirming the event itself is reflected in the block's receipts root.

This two-step verification ensures that validators attest only to cryptographically verified events while benefiting from the indexer's efficiency. When multiple deposits occur within the same block, validators can group the verified events and submit a single attestation for the final bridge root of that block. In periods with low transaction activity, validators may process each deposit event individually and submit separate attestations for each new bridge root.

### Immediate Pre-confirmation Process

The pre-confirmation system operates through immediate event-driven processing that handles both individual and aggregated validator attestations as they are submitted. When validators detect new bridge roots in block headers, they have two submission options depending on coordination with other validators.

**Coordinated Aggregation**: When multiple validators observe the same bridge root (common during stable periods), they coordinate off-chain to create aggregated BLS signatures. One validator submits the aggregated attestation containing all participant addresses and the single aggregated signature, providing significant gas savings for large validator participation.

**Individual Submission**: When validators observe different bridge roots due to timing differences, reorganizations, or different confirmation strategies, they submit individual attestations independently. This maintains system liveness and accuracy when validator views legitimately diverge.

Attestations are processed immediately upon submission regardless of format, with pre-confirmation status updated in real-time as attestations are received. This eliminates processing delays while providing instant feedback on pre-confirmation progress.

Once the pre-confirmation threshold is met—typically requiring attestations from 67% of active validators—the bridge root receives pre-confirmed status immediately. The system counts validator participation from both individual and aggregated attestations toward the threshold. This status is propagated to all destination networks through event emission, allowing users to process claims instantly without waiting for full cryptographic verification.

The immediate processing system enables instant cross-network settlement by relying on validator economic security while the SP1 verification mechanism continues to provide ultimate cryptographic assurance asynchronously.

### Asynchronous State Verification

The SP1 co-processor operates independently of pre-confirmation, continuously monitoring attestation events for batched proof generation. The SP1 system accumulates pre-confirmed attestations over time intervals and performs verification by fetching canonical network states through RPC connections.

The SP1 programme verifies that each pre-confirmed bridge root matches the actual bridge contract state at the claimed block. Upon successful verification, SP1 generates a Groth16 proof that all submitted bridge roots in the batch correctly represent actual network states.

This asynchronous verification provides final settlement and enables the system to detect and penalize any incorrect pre-confirmations. The off-chain batched approach amortizes proof generation costs across multiple attestations while maintaining comprehensive state verification without introducing on-chain complexity.

### Cross-network Block Coordination

Networks operate with different block times and finality requirements, creating coordination challenges for multi-network state verification. The system addresses this through flexible confirmation-based attestation rules rather than block-height synchronisation.

Validators submit attestations based on their network's finality rules—typically 12 confirmations for Ethereum, 1 confirmation for Polygon. The pre-confirmation system can proceed once sufficient validators attest, with immediate status updates eliminating coordination delays. SP1 verification ensures attestations are validated against finalised state only.

This approach accommodates networks with 12-second to 10-minute block times without requiring complex synchronisation protocols or waiting for the slowest network to finalise. The SP1 verification layer provides uniform security guarantees regardless of individual network finality characteristics.

### Claim Verification Process

When users claim assets on destination networks, they provide merkle proofs demonstrating their deposits exist within specific pre-confirmed bridge roots from source networks. The destination bridge contract performs two verification steps through interface abstraction that handles parameter construction automatically.

First, the contract confirms the provided bridge root has received pre-confirmation status by checking the pre-confirmation registry. This ensures only validator-attested bridge states are accepted for immediate claim processing.

Second, the contract validates the user's merkle proof against the pre-confirmed bridge root, confirming the claimed deposit actually exists within the attested state. If both verifications succeed, the bridge executes the asset transfer immediately.

This dual verification enables instant claims based on validator consensus while maintaining security through eventual SP1 verification of all pre-confirmed states.

## User Journey Analysis

### Cross-chain Transfer Initiation

Users interact with the bridge through standard transaction interfaces on their source network. The user specifies the destination network, recipient address, token type, and transfer amount. The bridge contract validates these parameters and processes the deposit immediately.

Upon successful deposit, users receive a deposit index and the corresponding bridge root that contains their deposit. Users can expect their deposits to become claimable within 30-60 seconds based on typical validator response times for pre-confirmation.

### Instant Pre-confirmation Period

After deposit submission, the transfer enters the pre-confirmation phase where validators attest to the new bridge state. Attestations are processed immediately upon submission, with pre-confirmation status updating in real-time as validator consensus is reached.

Users can monitor pre-confirmation progress through bridge interfaces that display live attestation collection status. Once pre-confirmation threshold is reached, the deposit becomes immediately claimable across destination networks with no additional processing delays.

### Asset Claiming Process

On the destination network, users submit claim transactions through bridge interfaces that automatically construct the necessary parameters and proofs. The interface generates the merkle proof and handles the technical complexity while presenting a simple claiming experience to users.

Successful claims trigger immediate asset transfers and update the destination network's claim tree, maintaining accurate accounting of all cross-network asset movements. Users receive their assets within the same transaction, experiencing instant cross-network settlement.

The interface abstraction ensures users need not understand the underlying technical requirements while maintaining the security guarantees of the cryptographic verification system.

## Security Architecture

### Cryptographic Verification Foundation

The system's ultimate security relies on zero-knowledge proof verification rather than economic consensus mechanisms. The SP1 co-processor provides mathematical guarantees that pre-confirmed bridge roots accurately represent network states, eliminating trust assumptions about validator honesty or network behaviour.

Groth16 proofs enable efficient on-chain verification of arbitrarily complex state verification logic. The asynchronous verification process ensures all pre-confirmed states receive cryptographic validation, providing final settlement guarantees regardless of pre-confirmation timing.

### Economic Incentive Layer

Pre-confirmation security relies on validator economic stakes and slashing mechanisms. Validators earn rewards for submitting accurate attestations that are later verified by SP1, creating positive incentives for honest participation regardless of whether attestations are submitted individually or in aggregated form.

Slashing mechanisms penalize validators who submit provably incorrect attestations during pre-confirmation. The SP1 verification system serves as the ultimate arbiter of truth, determining which attestations were objectively correct by verifying them against canonical chain state. Validators are only slashed when SP1 verification proves their attestations referenced bridge roots that never existed or state roots that don't match actual block state.

The slashing system distinguishes between legitimate differences in validator views (such as temporary reorganizations or timing differences) and provably malicious behavior. Validators who participate in aggregated signatures that later fail SP1 verification are held individually accountable through the participant tracking in aggregated attestations. The slashing rate scales with the severity and frequency of incorrect submissions, maintaining strong economic disincentives for dishonest behavior while allowing for legitimate operational differences.

### Multi-layer Defence Model

The combination of economic pre-confirmation and cryptographic verification creates a multi-layer defence system. Pre-confirmation provides immediate user experience based on validator consensus, while SP1 verification ensures long-term security through mathematical proof.

Even if pre-confirmation mechanisms fail due to validator collusion or failure, the SP1 verification system will detect incorrect attestations and enable recovery mechanisms. This design ensures the bridge maintains security under extreme scenarios while providing optimal user experience under normal conditions.

## Design Decision Rationale

### Two-phase Verification Architecture

The two-phase model addresses the fundamental tension between user experience and security in cross-network systems. Immediate cryptographic verification would require significant time for proof generation, creating poor user experience. Pure economic consensus without cryptographic backing would compromise security guarantees.

The immediate pre-confirmation phase provides instant settlement based on validator economic security, while asynchronous SP1 verification provides ultimate cryptographic guarantees. This approach achieves both immediate finality and mathematical security.

### Individual Processing with Off-Chain Batching

Processing deposits individually ensures immediate transaction finality while batching proof generation off-chain optimizes computational costs. This separation allows users to experience instant deposit confirmation while the system maintains economic efficiency in proof generation without on-chain complexity.

The architecture recognizes that user experience requirements differ from technical optimization requirements. Individual processing serves user needs while off-chain batched proof generation serves economic efficiency needs.

### SP1 and Groth16 Selection

Succinct Labs' SP1 was selected for its general-purpose zero-knowledge computation capabilities that enable verification of arbitrary network state transitions without requiring custom circuit development. SP1's Rust-based programming model allows complex verification logic that would be impractical in constraint-based proving systems.

Groth16 compression provides essential efficiency for on-chain verification. While alternative proving systems like PLONK offer universal setup properties, Groth16's minimal verification requirements and constant proof size make it optimal for networks with varying computational capabilities and gas pricing models.

### Pessimistic over Optimistic Security

Pessimistic proofs verify correctness upfront rather than assuming validity until challenged. This approach eliminates challenge periods and provides immediate finality once verification completes, which is crucial for bridge applications where incorrect state verification can result in permanent asset loss.

Optimistic systems create windows of vulnerability during challenge periods and require complex dispute resolution mechanisms. The pessimistic model's eventual verification provides stronger security guarantees suitable for high-value cross-network transfers.

### Dual Attestation Submission Strategy

The system supports both individual and aggregated BLS attestations to optimize for different operational scenarios. Pure aggregated signatures would be most gas-efficient but could fail during network instability when validators have legitimately different views of chain state. Pure individual signatures would be most flexible but sacrifice gas efficiency when validators agree.

The dual approach recognizes that validators will often converge on the same finalized bridge root during stable periods, enabling gas optimization through BLS aggregation. During edge cases such as reorganizations, different confirmation strategies, or high-frequency deposit periods, validators can fall back to individual submissions without compromising system liveness.

This design maintains both economic efficiency and operational resilience. Aggregated submissions provide significant gas savings when validators naturally coordinate, while individual submissions ensure the system remains responsive when coordination is not possible. The SP1 verification system provides consistent security guarantees regardless of submission method, as all attestations undergo the same cryptographic verification process.

### Immediate Event-Driven Processing

The immediate processing approach for pre-confirmation eliminates gas costs, processing bottlenecks, and coordination problems associated with on-chain queue management. Event-driven architecture enables real-time pre-confirmation status updates while maintaining decentralized operation.

This design separates concerns appropriately: on-chain processing handles immediate state updates and event emission, while off-chain systems handle batched proof generation for economic efficiency. The approach avoids MEV opportunities and manipulation vectors that queue-based systems would introduce.

### Validator Block Header Monitoring

Direct block header querying by validators ensures access to canonical network state while maintaining decentralized monitoring. This approach prevents the centralization risks of requiring networks to submit data to the bridge system while ensuring validators access authoritative state information.

Block header monitoring provides natural integration with existing network infrastructure, as validators can use standard RPC endpoints without requiring special bridge-specific APIs from network operators.

## Operational Characteristics

### Pre-confirmation Latency and Throughput

Pre-confirmation completes immediately upon reaching validator consensus threshold through real-time attestation processing. The dual submission approach (individual and aggregated attestations) provides optimal performance under different network conditions while maintaining economic security guarantees without introducing processing delays.

**Stable Periods**: During stable network conditions when validators agree on bridge roots, aggregated signatures provide maximum gas efficiency. A single aggregated attestation representing dozens of validators can achieve pre-confirmation threshold instantly with minimal gas costs.

**Dynamic Periods**: During reorganizations or high-frequency deposit periods when validators may have different views, individual attestations ensure system liveness and accuracy. Validators can submit attestations independently without waiting for coordination, maintaining responsiveness.

The immediate processing system can handle unlimited transaction volume, as verification cost scales with attestation processing efficiency rather than transaction count. BLS signature verification (both individual and aggregated) provides constant or near-constant verification costs, enabling high-throughput cross-network settlement without compromising response times.

### Asynchronous Verification Performance

SP1 proof generation operates independently of user-facing settlement, completing within the time required for batched proof generation depending on computational load and batch complexity. This asynchronous approach ensures user experience remains optimal regardless of verification latency.

The verification system can process thousands of cross-network transfers per proof batch while maintaining comprehensive state verification across all connected networks. The off-chain batched approach provides significant cost advantages over individual proof generation while eliminating on-chain complexity.

### Network Integration Requirements

Adding new networks requires minimal protocol modifications. Validators begin monitoring new network block headers and the SP1 verification logic adapts to include new network state verification. This extensibility enables rapid network addition without requiring consensus changes or validator set updates.

Networks must implement compatible bridge contracts and provide RPC access for block header queries. The SP1 system handles varying network architectures and consensus mechanisms through its general-purpose verification capabilities.

### Scalability Properties

The system scales horizontally through validator distribution across network subsets while maintaining security through cryptographic verification. BLS signature aggregation ensures pre-confirmation costs remain constant regardless of validator set growth.

Groth16 proof verification provides constant-cost validation regardless of computation complexity, enabling the system to support arbitrarily complex cross-network verification logic without affecting destination network performance.

Cross-network throughput scales with immediate processing capabilities and validator response times. The event-driven system enables instant settlement while asynchronous verification provides final security guarantees through off-chain batched proof generation.
