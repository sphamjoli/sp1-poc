use bridge_program::rlp::{list_items, parse_item};

// ---- single-byte range ----

#[test]
fn single_byte_zero() {
    let data = [0x00u8];
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(!item.is_list);
    assert_eq!(item.payload, &[0x00u8]);
    assert_eq!(next, 1);
}

#[test]
fn single_byte_max() {
    let data = [0x7fu8];
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(!item.is_list);
    assert_eq!(item.payload, &[0x7f]);
    assert_eq!(next, 1);
}

// ---- short string (0x80..0xb7) ----

#[test]
fn empty_string() {
    // 0x80 = empty string
    let data = [0x80u8];
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(!item.is_list);
    assert_eq!(item.payload.len(), 0);
    assert_eq!(next, 1);
}

#[test]
fn short_string_abc() {
    // [0x83, 'a', 'b', 'c']
    let data = [0x83u8, b'a', b'b', b'c'];
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(!item.is_list);
    assert_eq!(item.payload, b"abc");
    assert_eq!(next, 4);
}

#[test]
fn short_string_max_55_bytes() {
    // 55-byte string: header = 0x80 + 55 = 0xb7
    let payload: Vec<u8> = (0u8..55).collect();
    let mut data = vec![0xb7u8];
    data.extend_from_slice(&payload);
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(!item.is_list);
    assert_eq!(item.payload, payload.as_slice());
    assert_eq!(next, data.len());
}

// ---- long string (0xb8..0xbf) ----

#[test]
fn long_string_56_bytes() {
    // 56-byte string: 0xb8, 0x38 (len=56), then 56 bytes
    let payload = vec![0xaau8; 56];
    let mut data = vec![0xb8u8, 56u8];
    data.extend_from_slice(&payload);
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(!item.is_list);
    assert_eq!(item.payload, payload.as_slice());
    assert_eq!(next, data.len());
}

// ---- short list (0xc0..0xf7) ----

#[test]
fn empty_list() {
    let data = [0xc0u8];
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(item.is_list);
    let items = list_items(item.payload).unwrap();
    assert_eq!(items.len(), 0);
    assert_eq!(next, 1);
}

#[test]
fn short_list_three_single_bytes() {
    // list of [0x01, 0x02, 0x03] → 3 bytes payload → 0xc0+3 = 0xc3
    let data = [0xc3u8, 0x01, 0x02, 0x03];
    let (item, next) = parse_item(&data, 0).unwrap();
    assert!(item.is_list);
    let items = list_items(item.payload).unwrap();
    assert_eq!(items.len(), 3);
    assert_eq!(items[0].payload, &[0x01]);
    assert_eq!(items[1].payload, &[0x02]);
    assert_eq!(items[2].payload, &[0x03]);
    assert_eq!(next, 4);
}

#[test]
fn nested_list() {
    // outer list containing one inner empty list: [0xc1, 0xc0]
    let data = [0xc1u8, 0xc0u8];
    let (outer, _) = parse_item(&data, 0).unwrap();
    assert!(outer.is_list);
    let outer_items = list_items(outer.payload).unwrap();
    assert_eq!(outer_items.len(), 1);
    assert!(outer_items[0].is_list);
    let inner_items = list_items(outer_items[0].payload).unwrap();
    assert_eq!(inner_items.len(), 0);
}

// ---- error cases ----

#[test]
fn truncated_string_payload() {
    // claims 3 bytes but only 1 follows
    let data = [0x83u8, b'a'];
    assert!(parse_item(&data, 0).is_err());
}

#[test]
fn offset_past_end() {
    let data = [0x01u8];
    assert!(parse_item(&data, 5).is_err());
}

#[test]
fn truncated_long_string_length() {
    // 0xb8 means 1-byte length follows, but nothing follows
    let data = [0xb8u8];
    assert!(parse_item(&data, 0).is_err());
}

// ---- parse_item with non-zero offset ----

#[test]
fn parse_with_offset() {
    // [garbage, 0x83, 'x', 'y', 'z'] — start at offset 1
    let data = [0xff, 0x83u8, b'x', b'y', b'z'];
    let (item, next) = parse_item(&data, 1).unwrap();
    assert_eq!(item.payload, b"xyz");
    assert_eq!(next, 5);
}

use proptest::prelude::*;

proptest! {
    #[test]
    fn arbitrary_rlp_never_panics_and_advances_within_input(
        data in proptest::collection::vec(any::<u8>(), 0..1024),
        offset in any::<usize>(),
    ) {
        if let Ok((item, next)) = parse_item(&data, offset) {
            prop_assert!(next > offset);
            prop_assert!(next <= data.len());
            prop_assert!(item.payload.len() <= next - offset);
        }
    }

    #[test]
    fn oversized_lengths_are_rejected(
        length in (usize::MAX - 8)..=usize::MAX,
        is_list in any::<bool>(),
        offset in 0usize..16,
    ) {
        let mut data = vec![0; offset];
        data.push(if is_list { 0xff } else { 0xbf });
        data.extend_from_slice(&(length as u64).to_be_bytes());
        prop_assert!(parse_item(&data, offset).is_err());
    }

    #[test]
    fn redundant_single_byte_prefix_is_rejected(byte in 0u8..=0x7f) {
        prop_assert!(parse_item(&[0x81, byte], 0).is_err());
    }

    #[test]
    fn non_canonical_long_lengths_are_rejected(
        length in 0u8..56,
        is_list in any::<bool>(),
        leading_zero in any::<bool>(),
    ) {
        let base = if is_list { 0xf7 } else { 0xb7 };
        let mut data = if leading_zero { vec![base + 2, 0, length] } else { vec![base + 1, length] };
        data.extend(vec![0x80; usize::from(length)]);
        prop_assert!(parse_item(&data, 0).is_err());
    }
}
