use crate::rlp_helpers::{concat, rlp_list, rlp_string};

/// Build an RLP-encoded receipt with one log.
/// Receipt: RLP([status=1, cumGasUsed=21000, logsBloom=256zeros, logs=[log]])
/// Log: RLP([address_20bytes, [topic0, topic1, topic2, topic3], data])
pub fn build_receipt_with_log(
    log_address: [u8; 20],
    topics: &[[u8; 32]],
    log_data: &[u8],
) -> Vec<u8> {
    let encoded_topics: Vec<Vec<u8>> = topics.iter().map(|t| rlp_string(t)).collect();
    let topics_payload = concat(&encoded_topics);
    let topics_list = rlp_list(&topics_payload);

    let log_payload = concat(&[rlp_string(&log_address), topics_list, rlp_string(log_data)]);
    let log_encoded = rlp_list(&log_payload);

    let logs_payload = log_encoded;
    let logs_list = rlp_list(&logs_payload);

    let bloom = [0u8; 256];
    let gas_used: u64 = 21000;
    let gas_used_bytes: Vec<u8> = {
        let b = gas_used.to_be_bytes();
        b.iter().skip_while(|&&x| x == 0).copied().collect()
    };

    let receipt_payload = concat(&[
        rlp_string(&[0x01]),         // status
        rlp_string(&gas_used_bytes), // cumGasUsed
        rlp_string(&bloom),          // logsBloom
        logs_list,                   // logs
    ]);
    rlp_list(&receipt_payload)
}
