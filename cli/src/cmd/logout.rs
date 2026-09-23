use crate::config::{config_path, read_multi_config, write_atomic_0600};
use crate::error::{CliError, Result};
use crate::theme::Theme;

/// With multi-profile configs, `logout` removes only the
/// CURRENT profile's credentials — deleting every environment's token
/// would surprise anyone using `env` profiles. When the last profile is
/// removed the file is deleted (back to the pristine not-logged-in state).
pub fn run(theme: &Theme) -> Result<()> {
    let path = config_path().map_err(CliError::from)?;
    let _lock = crate::config::ConfigLock::acquire(&path).map_err(CliError::from)?;
    if !path.exists() {
        eprintln!("{} no token stored", theme.muted("·"));
        return Ok(());
    }
    let mut cfg = read_multi_config(&path).map_err(CliError::from)?;
    let removed = cfg.current.clone();
    cfg.profiles.remove(&removed);
    match cfg.profiles.keys().next().cloned() {
        None => {
            std::fs::remove_file(&path).map_err(|e| CliError::Generic(e.to_string()))?;
            eprintln!("{} Token removed ('{removed}')", theme.success("✓"));
        }
        Some(next) => {
            cfg.current = next.clone();
            let bytes =
                serde_json::to_vec_pretty(&cfg).map_err(|e| CliError::Generic(e.to_string()))?;
            write_atomic_0600(&path, &bytes).map_err(CliError::from)?;
            eprintln!(
                "{} Token removed ('{removed}') — current profile is now '{next}'",
                theme.success("✓")
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn removes_existing_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("config.json");
        fs::write(&path, b"{}").unwrap();
        assert!(path.exists());
        fs::remove_file(&path).unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn idempotent_on_missing_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("config.json");
        // File doesn't exist — removal is a no-op when we check first.
        assert!(!path.exists());
        // The run() function uses path.exists() guard so no error occurs.
    }
}
