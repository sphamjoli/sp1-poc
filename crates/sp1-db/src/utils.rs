pub static DEPOSIT_QUERY_ALL: &str = r#"
                query GetDeposits {
                    Deposit {
                        id
                        gasUsed
                        to
                        amount
                        timestamp
                        transactionHash
                        sourceChain
                        destinationChain
                        blockNumber
                        depositRoot
                        depositIndex
                        who
                        user_id
                        token_id
                    }
                }
            "#;

pub static CLAIM_QUERY_ALL: &str = r#"
                query GetClaims {
                    Claim {
                        id
                        gasUsed
                        to
                        amount
                        timestamp
                        transactionHash
                        sourceChain
                        destinationChain
                        proofBytes
                        publicInputs
                        user_id
                        token_id
                    }
                }
            "#;

pub static ATTESTATION_QUERY_ALL: &str = r#"
query AttestationAll {
  Attestation {
    blockNumber
    blockTimestamp
    transactionHash
    logIndex
    gasPrice
    gasUsed

    validator
    validatorManager

    sourceChainId
    sourceBlockNumber
    bridgeRoot
    stateRoot
    timestamp
  }
}
"#;
