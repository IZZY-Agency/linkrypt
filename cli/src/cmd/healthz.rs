use crate::api::Client;
use crate::config::{resolve_url_for_unauthenticated, validate_https};
use crate::error::Result;
use crate::theme::Theme;

pub fn run(url_override: Option<String>, verbose: bool, theme: &Theme) -> Result<()> {
    // After `env use <name>`, a bare `healthz` must probe the CURRENT
    // profile, not the built-in default. Explicit --url /
    // LINKRYPT_API_URL still win (url_override carries both via clap env).
    let url = url_override.or_else(|| std::env::var("LINKRYPT_API_URL").ok());
    let url = resolve_url_for_unauthenticated(url.as_deref());
    validate_https(&url)?;

    // healthz needs no auth — pass empty token.
    let client = Client::new(url, String::new(), verbose);
    let data = client.healthz()?;
    let ok = data.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
    println!(
        "{} {}",
        if ok {
            theme.success("✓")
        } else {
            theme.error("✗")
        },
        if ok { "healthy" } else { "unhealthy" }
    );
    if let Some(checks) = data.get("checks").and_then(|v| v.as_array()) {
        for c in checks {
            println!("  {}", c.as_str().unwrap_or("?"));
        }
    }
    Ok(())
}
