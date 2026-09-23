use crate::api::Client;
use crate::config::{resolve_token_and_url, validate_https};
use crate::error::Result;
use crate::theme::Theme;

pub fn run(
    url_override: Option<String>,
    limit: Option<u32>,
    verbose: bool,
    theme: &Theme,
) -> Result<()> {
    let (token, url) = resolve_token_and_url(url_override.as_deref())?;
    validate_https(&url)?;
    let client = Client::new(url, token, verbose);
    let data = client.audit(limit)?;
    let events = data
        .get("events")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if events.is_empty() {
        println!("{} no audit events", theme.muted("·"));
        return Ok(());
    }

    println!(
        "{:<22} {:<22} {:<28} {:<14} {}",
        theme.accent("when"),
        theme.accent("event"),
        theme.accent("target"),
        theme.accent("actor"),
        theme.accent("country")
    );
    for e in events {
        let when = e.get("at").and_then(|v| v.as_str()).unwrap_or("—");
        let event = e.get("eventType").and_then(|v| v.as_str()).unwrap_or("?");
        // targetId falls back to shareId (legacy field name)
        let tid = e
            .get("targetId")
            .or_else(|| e.get("shareId"))
            .and_then(|v| v.as_str())
            .unwrap_or("—");
        let tid_short = if tid.len() > 10 {
            format!("{}…", &tid[..10])
        } else {
            tid.to_string()
        };
        let ttype = e
            .get("targetType")
            .and_then(|v| v.as_str())
            .unwrap_or("share");
        let target = format!("{}/{}", ttype, tid_short);
        let actor = e.get("actor").and_then(|v| v.as_str()).unwrap_or("?");
        let country = e.get("country").and_then(|v| v.as_str()).unwrap_or("—");
        println!(
            "{:<22} {:<22} {:<28} {:<14} {}",
            theme.muted(when),
            event,
            target,
            actor,
            country
        );
    }
    Ok(())
}
