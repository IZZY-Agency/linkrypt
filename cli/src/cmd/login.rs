use crate::api::Client;
use crate::config::{
    config_path, read_multi_config, validate_https, write_atomic_0600, MultiConfig, DEFAULT_API_URL,
};
use crate::error::{CliError, Result};
use crate::theme::Theme;

pub fn run(url_override: Option<String>, theme: &Theme) -> Result<()> {
    let url = url_override
        .or_else(|| std::env::var("LINKRYPT_API_URL").ok())
        .unwrap_or_else(|| DEFAULT_API_URL.to_string());

    validate_https(&url).map_err(|e| CliError::BadUsage(e.to_string()))?;

    eprint!(
        "{}",
        theme.accent(&format!("Paste your token from {url}/app/tokens: "))
    );
    let token = rpassword::read_password().map_err(|e| CliError::Generic(e.to_string()))?;
    let token = token.trim().to_string();

    // API tokens are issued with the `lk_` prefix.
    if !token.starts_with("lk_") {
        return Err(CliError::BadUsage(
            "that doesn't look like an lk_ token".into(),
        ));
    }

    // Validate by hitting /api/cli/whoami with the token.
    // /api/healthz is unauthenticated and would let a bogus token through.
    let client = Client::new(url.clone(), token.clone(), false);
    client.whoami().map_err(map_whoami_err)?;

    // The config is multi-profile. `login` updates the CURRENT
    // profile (creating "default" on first run); other profiles keep
    // their credentials. Legacy single-shape configs soft-migrate here.
    let path = config_path().map_err(CliError::from)?;
    // Lock across the read-modify-write so concurrent invocations cannot
    // lose each other's updates; acquired after the token prompt so it is
    // never held on user input.
    let _lock = crate::config::ConfigLock::acquire(&path).map_err(CliError::from)?;
    let mut cfg = if path.exists() {
        read_multi_config(&path).map_err(CliError::from)?
    } else {
        MultiConfig {
            current: "default".to_string(),
            profiles: Default::default(),
        }
    };
    let current = cfg.current.clone();
    cfg.add(&current, &url, &token); // add() also keeps `current` pointed here
    let bytes = serde_json::to_vec_pretty(&cfg).map_err(|e| CliError::Generic(e.to_string()))?;
    write_atomic_0600(&path, &bytes).map_err(CliError::from)?;

    eprintln!(
        "{} Saved ({}, chmod 600)",
        theme.success("✓"),
        path.display()
    );
    Ok(())
}

/// Map a `whoami` failure during `login`. Only an explicit unauthorized
/// response means the pasted token is bad; server/network failures (the
/// server's owner lookup fails closed) keep their typed variant so the
/// user is not told to remint a perfectly good token.
pub(crate) fn map_whoami_err(e: anyhow::Error) -> CliError {
    match CliError::from(e) {
        CliError::Unauthorized(m) => {
            CliError::Unauthorized(format!("token rejected by server: {m}"))
        }
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Only an explicit unauthorized response means the pasted token is bad.
    // Server/network failures (the whoami user lookup fails closed
    // server-side) must NOT be reported as "token rejected" — that message
    // tells the user to remint a good token.

    #[test]
    fn whoami_unauthorized_maps_to_token_rejected() {
        let e = anyhow::anyhow!("unauthorized — bad token");
        match map_whoami_err(e) {
            CliError::Unauthorized(m) => {
                assert!(m.contains("token rejected by server"), "got: {m}")
            }
            other => panic!("expected Unauthorized, got {other:?}"),
        }
    }

    #[test]
    fn whoami_server_error_stays_generic_not_token_rejected() {
        let e = anyhow::anyhow!("server error (http 500)");
        match map_whoami_err(e) {
            CliError::Generic(m) => {
                assert!(!m.contains("token rejected"), "got: {m}")
            }
            other => panic!("expected Generic, got {other:?}"),
        }
    }
}
