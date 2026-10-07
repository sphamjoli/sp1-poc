extern crate alloc;

use alloc::vec::Vec;
use sp1_types::{ProgramError, ProgramResult};

pub struct RlpItem<'a> {
    pub is_list: bool,
    pub payload: &'a [u8],
}

pub fn parse_item<'a>(input: &'a [u8], offset: usize) -> ProgramResult<(RlpItem<'a>, usize)> {
    if offset >= input.len() {
        return Err(ProgramError::RlpInvalid);
    }

    let first = input[offset];

    if first <= 0x7f {
        return Ok((RlpItem { is_list: false, payload: &input[offset..offset + 1] }, offset + 1));
    }

    if first <= 0xb7 {
        let len = (first - 0x80) as usize;
        let start = offset + 1;
        let end = start.checked_add(len).ok_or(ProgramError::RlpInvalid)?;
        if end > input.len() {
            return Err(ProgramError::RlpInvalid);
        }
        if len == 1 && input[start] <= 0x7f {
            return Err(ProgramError::RlpInvalid);
        }
        return Ok((RlpItem { is_list: false, payload: &input[start..end] }, end));
    }

    if first <= 0xbf {
        let len_of_len = (first - 0xb7) as usize;
        let start_len = offset + 1;
        let end_len = start_len + len_of_len;
        if end_len > input.len() {
            return Err(ProgramError::RlpInvalid);
        }
        if input[start_len] == 0 {
            return Err(ProgramError::RlpInvalid);
        }
        let mut len: usize = 0;
        for &b in &input[start_len..end_len] {
            len = len
                .checked_mul(256)
                .and_then(|value| value.checked_add(b as usize))
                .ok_or(ProgramError::RlpInvalid)?;
        }
        if len < 56 {
            return Err(ProgramError::RlpInvalid);
        }
        let start = end_len;
        let end = start.checked_add(len).ok_or(ProgramError::RlpInvalid)?;
        if end > input.len() {
            return Err(ProgramError::RlpInvalid);
        }
        return Ok((RlpItem { is_list: false, payload: &input[start..end] }, end));
    }

    if first <= 0xf7 {
        let len = (first - 0xc0) as usize;
        let start = offset + 1;
        let end = start.checked_add(len).ok_or(ProgramError::RlpInvalid)?;
        if end > input.len() {
            return Err(ProgramError::RlpInvalid);
        }
        return Ok((RlpItem { is_list: true, payload: &input[start..end] }, end));
    }

    let len_of_len = (first - 0xf7) as usize;
    let start_len = offset + 1;
    let end_len = start_len + len_of_len;
    if end_len > input.len() {
        return Err(ProgramError::RlpInvalid);
    }
    if input[start_len] == 0 {
        return Err(ProgramError::RlpInvalid);
    }
    let mut len: usize = 0;
    for &b in &input[start_len..end_len] {
        len = len
            .checked_mul(256)
            .and_then(|value| value.checked_add(b as usize))
            .ok_or(ProgramError::RlpInvalid)?;
    }
    if len < 56 {
        return Err(ProgramError::RlpInvalid);
    }
    let start = end_len;
    let end = start.checked_add(len).ok_or(ProgramError::RlpInvalid)?;
    if end > input.len() {
        return Err(ProgramError::RlpInvalid);
    }
    Ok((RlpItem { is_list: true, payload: &input[start..end] }, end))
}

pub fn list_items<'a>(list_payload: &'a [u8]) -> ProgramResult<Vec<RlpItem<'a>>> {
    let mut items = Vec::new();
    let mut offset = 0usize;
    while offset < list_payload.len() {
        let (item, next) = parse_item(list_payload, offset)?;
        items.push(item);
        offset = next;
    }
    Ok(items)
}
