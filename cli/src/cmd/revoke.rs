use crate::api::Client;
use crate::config::{resolve_token_and_url, validate_https};
use crate::error::Result;
use crate::theme::Theme;

pub fn run(url_override: Option<String>, id: String, verbose: bool, theme: &Theme) -> Result<()> {
    let (token, url) = resolve_token_and_url(url_override.as_deref())?;
    validate_https(&url)?;
    let client = Client::new(url, token, verbose);
    client.revoke_share(&id)?;
    println!("{} revoked {}", theme.success("✓"), theme.muted(&id));
    Ok(())
}
