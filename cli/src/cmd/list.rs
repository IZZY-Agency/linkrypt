use crate::api::Client;
use crate::config::{resolve_token_and_url, validate_https};
use crate::error::Result;
use crate::theme::Theme;

pub fn run(url_override: Option<String>, verbose: bool, theme: &Theme) -> Result<()> {
    let (token, url) = resolve_token_and_url(url_override.as_deref())?;
    validate_https(&url)?;
    let client = Client::new(url, token, verbose);
    let data = client.list_shares()?;

    let shares = data
        .get("shares")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if shares.is_empty() {
        println!("{} no active shares", theme.muted("·"));
        return Ok(());
    }

    println!(
        "{:<12} {:<6} {:<24} {:<7} {:<20} {}",
        theme.accent("id"),
        theme.accent("type"),
        theme.accent("label"),
        theme.accent("opens"),
        theme.accent("expires"),
        theme.accent("created")
    );
    for s in shares {
        let id = s.get("id").and_then(|v| v.as_str()).unwrap_or("?");
        let id_short = if id.len() > 10 {
            format!("{}…", &id[..10])
        } else {
            id.to_string()
        };
        let typ = s.get("type").and_then(|v| v.as_str()).unwrap_or("?");
        let label = s
            .get("label")
            .and_then(|v| v.as_str())
            .unwrap_or("(unlabelled)");
        let opens = format!(
            "{}/{}",
            s.get("opensUsed").and_then(|v| v.as_u64()).unwrap_or(0),
            s.get("maxOpens").and_then(|v| v.as_u64()).unwrap_or(0)
        );
        let expires = s.get("expiresAt").and_then(|v| v.as_str()).unwrap_or("—");
        let created = s.get("createdAt").and_then(|v| v.as_str()).unwrap_or("—");
        println!(
            "{:<12} {:<6} {:<24} {:<7} {:<20} {}",
            id_short,
            typ,
            label,
            opens,
            expires,
            theme.muted(created)
        );
    }
    Ok(())
}
