//! env.rs — named environment profiles.
//!
//! `<bin> env list`            list profiles, mark the current one
//! `<bin> env use <name>`      switch the `current` pointer
//! `<bin> env add <name> --url <url>`  create a profile (login flow) + switch to it
//! `<bin> env remove <name>`   delete a non-current profile
//!
//! Precedence is unchanged: `--url` / `LINKRYPT_API_URL` / `LINKRYPT_API_TOKEN`
//! still override the current profile ad hoc (see config::resolve_token_and_url).

use crate::api::Client;
use crate::cmd::login::map_whoami_err;
use crate::config::{
    config_path, read_multi_config, validate_https, write_atomic_0600, ConfigLock, MultiConfig,
};
use crate::error::{CliError, Result};
use crate::theme::Theme;

fn load() -> Result<(std::path::PathBuf, MultiConfig)> {
    let path = config_path().map_err(CliError::from)?;
    if !path.exists() {
        return Err(CliError::BadUsage(
            "no config yet — run 'login' (creates the 'default' profile) or 'env add'".into(),
        ));
    }
    let cfg = read_multi_config(&path).map_err(CliError::from)?;
    Ok((path, cfg))
}

fn save(path: &std::path::Path, cfg: &MultiConfig) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(cfg).map_err(|e| CliError::Generic(e.to_string()))?;
    write_atomic_0600(path, &bytes).map_err(CliError::from)?;
    Ok(())
}

pub fn list(theme: &Theme) -> Result<()> {
    let (_, cfg) = load()?;
    for (name, profile) in &cfg.profiles {
        // Never print tokens — names + URLs only.
        if *name == cfg.current {
            eprintln!("{} {name}  {}", theme.success("*"), profile.url);
        } else {
            eprintln!("  {name}  {}", theme.muted(&profile.url));
        }
    }
    Ok(())
}

pub fn use_profile(name: &str, theme: &Theme) -> Result<()> {
    let lock_path = config_path().map_err(CliError::from)?;
    let _lock = ConfigLock::acquire(&lock_path).map_err(CliError::from)?;
    let (path, mut cfg) = load()?;
    cfg.switch(name)
        .map_err(|e| CliError::BadUsage(e.to_string()))?;
    save(&path, &cfg)?;
    let url = &cfg.profiles[name].url;
    eprintln!("{} current profile: {name} ({url})", theme.success("✓"));
    Ok(())
}

pub fn add(name: &str, url_arg: Option<String>, theme: &Theme) -> Result<()> {
    let url = url_arg.ok_or_else(|| CliError::BadUsage("env add requires --url <url>".into()))?;
    let url = url.trim_end_matches('/').to_string();
    validate_https(&url).map_err(|e| CliError::BadUsage(e.to_string()))?;

    // Same login flow as `login`: paste token, verify against whoami so a
    // bogus token never lands in the config.
    eprint!(
        "{}",
        theme.accent(&format!("Paste your token from {url}/app/tokens: "))
    );
    let token = rpassword::read_password().map_err(|e| CliError::Generic(e.to_string()))?;
    let token = token.trim().to_string();
    if !token.starts_with("lk_") {
        return Err(CliError::BadUsage(
            "that doesn't look like an lk_ token".into(),
        ));
    }
    let client = Client::new(url.clone(), token.clone(), false);
    client.whoami().map_err(map_whoami_err)?;

    // Lock across the read-modify-write so concurrent invocations cannot
    // lose each other's updates — acquired AFTER the interactive prompt so
    // the lock is never held while waiting on a human.
    let path = config_path().map_err(CliError::from)?;
    let _lock = ConfigLock::acquire(&path).map_err(CliError::from)?;
    // First `env add` on a machine with no config yet starts an empty set.
    let mut cfg = if path.exists() {
        read_multi_config(&path).map_err(CliError::from)?
    } else {
        MultiConfig {
            current: name.to_string(),
            profiles: Default::default(),
        }
    };
    // Refuse to silently overwrite an existing profile's credentials.
    if cfg.profiles.contains_key(name) {
        return Err(CliError::BadUsage(format!(
            "profile '{name}' already exists — 'env use {name}' + 'login' updates it, \
             or 'env remove {name}' first"
        )));
    }
    cfg.add(name, &url, &token); // also switches current to `name`
    save(&path, &cfg)?;
    eprintln!(
        "{} profile '{name}' saved and selected ({url})",
        theme.success("✓")
    );
    Ok(())
}

pub fn remove(name: &str, theme: &Theme) -> Result<()> {
    let lock_path = config_path().map_err(CliError::from)?;
    let _lock = ConfigLock::acquire(&lock_path).map_err(CliError::from)?;
    let (path, mut cfg) = load()?;
    cfg.remove(name)
        .map_err(|e| CliError::BadUsage(e.to_string()))?;
    save(&path, &cfg)?;
    eprintln!("{} profile '{name}' removed", theme.success("✓"));
    Ok(())
}
