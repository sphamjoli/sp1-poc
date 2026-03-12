use crate::runtime::LoadedRuntime;
use eyre::{Result, WrapErr};
use serde::Serialize;
use std::fs;
use std::path::Path;

pub fn write_state_file<T: Serialize>(
    runtime: &LoadedRuntime,
    relative_path: impl AsRef<Path>,
    value: &T,
) -> Result<()> {
    let file_path = runtime.state_path(relative_path);
    if let Some(parent_directory) = file_path.parent() {
        fs::create_dir_all(parent_directory)
            .wrap_err_with(|| format!("failed to create {}", parent_directory.display()))?;
    }

    fs::write(&file_path, serde_json::to_vec_pretty(value)?)
        .wrap_err_with(|| format!("failed to write {}", file_path.display()))?;
    Ok(())
}
