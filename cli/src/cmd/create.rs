use crate::api::{Client, CreateShareReq};
use crate::config::{resolve_token_and_url, validate_https};
use crate::crypto::{
    aes_encrypt, b64u_encode, pbkdf2_derive, random_bytes, AES_IV_LEN, AES_KEY_LEN,
    MAX_FILE_SIZE_CIPHERTEXT, MAX_TEXT_SIZE_CIPHERTEXT, PBKDF2_SALT_LEN,
};
use crate::error::{CliError, Result};
use crate::input::{resolve, Source};
use crate::progress::maybe_bar;
use crate::theme::Theme;
use crate::CreateArgs;

pub fn run(
    url_override: Option<String>,
    args: CreateArgs,
    verbose: bool,
    theme: &Theme,
) -> Result<()> {
    let (token, url) = resolve_token_and_url(url_override.as_deref())?;
    validate_https(&url)?;

    // Validate --to before encrypting so a typo fails fast.
    if let Some(ref to) = args.to {
        if !looks_like_email(to) {
            return Err(CliError::BadUsage(format!("invalid --to address: {to}")));
        }
    }

    // Resolve content.
    let source = resolve(
        args.text.as_deref(),
        args.file.as_deref(),
        args.filename.as_deref(),
    )?;
    let (kind, plaintext, filename) = match source {
        Source::Text(s) => ("text", s.into_bytes(), None),
        Source::Binary { bytes, filename } => ("file", bytes, Some(filename)),
    };

    // Pre-encrypt cap check: plaintext + 16-byte GCM tag must not exceed cap.
    let cap = if kind == "file" {
        MAX_FILE_SIZE_CIPHERTEXT
    } else {
        MAX_TEXT_SIZE_CIPHERTEXT
    };
    if plaintext.len() + 16 > cap {
        return Err(CliError::BadUsage(format!(
            "content too large: plaintext {} bytes + 16-byte tag > {} cap",
            plaintext.len(),
            cap
        )));
    }

    // Optional passphrase: Some("") → prompt; Some(non-empty) → use + warn; None → no passphrase.
    let passphrase_opt: Option<String> = match &args.passphrase {
        Some(s) if s.is_empty() => {
            eprint!("{}", theme.accent("Passphrase: "));
            Some(rpassword::read_password().map_err(|e| CliError::Generic(e.to_string()))?)
        }
        Some(s) => {
            eprintln!(
                "{}",
                theme.muted("warning: passphrase visible in shell history")
            );
            Some(s.clone())
        }
        None => None,
    };
    let (passphrase_salt_b64u, passphrase_hash_b64u) = match passphrase_opt.as_deref() {
        Some(pp) if !pp.is_empty() => {
            let salt = random_bytes(PBKDF2_SALT_LEN);
            let hash = pbkdf2_derive(pp, &salt);
            (Some(b64u_encode(&salt)), Some(b64u_encode(&hash)))
        }
        _ => (None, None),
    };

    // Encrypt: random 32-byte key + 12-byte IV → AES-256-GCM.
    let mut key = [0u8; AES_KEY_LEN];
    let mut iv = [0u8; AES_IV_LEN];
    key.copy_from_slice(&random_bytes(AES_KEY_LEN));
    iv.copy_from_slice(&random_bytes(AES_IV_LEN));
    let ciphertext = aes_encrypt(&key, &iv, &plaintext)?;
    // Paranoid post-check (should never fire given the pre-check above).
    if ciphertext.len() > cap {
        return Err(CliError::Generic(
            "encrypted size exceeds cap (internal bug)".to_string(),
        ));
    }

    // Build API request and send to server.
    let client = Client::new(url.clone(), token, verbose);
    let req = CreateShareReq {
        r#type: kind,
        size: ciphertext.len(),
        expires_in: &args.expires,
        max_opens: args.opens,
        label: args.label.as_deref(),
        filename: filename.as_deref(),
        recipient_email: args.to.as_deref(),
        notify_on_open: if args.notify_on_open {
            Some(true)
        } else {
            None
        },
        passphrase_salt: passphrase_salt_b64u.as_deref(),
        passphrase_hash: passphrase_hash_b64u.as_deref(),
    };
    let resp = client.create_share(&req)?;

    // Upload ciphertext.
    if kind == "file" {
        let upload_url = resp.upload_url.as_ref().ok_or_else(|| {
            CliError::Generic("server did not return uploadUrl for file share".to_string())
        })?;

        // Progress bar for uploads > 1 MiB.
        let pb = maybe_bar(ciphertext.len(), "uploading", true);
        let progress_cb = pb.as_ref().map(|bar| {
            let bar = bar.clone();
            move |n: usize| bar.set_position(n as u64)
        });
        client.put_r2_with_progress(upload_url, &ciphertext, progress_cb)?;
        if let Some(bar) = pb {
            bar.finish_and_clear();
        }

        // Single retry for finalize (the endpoint is idempotent).
        if let Err(e) = client.finalize_file(&resp.id) {
            client.finalize_file(&resp.id).map_err(|_| e)?;
        }
    } else {
        // Single retry for finalize (the endpoint is idempotent).
        if let Err(e) = client.finalize_text(&resp.id, &ciphertext) {
            client.finalize_text(&resp.id, &ciphertext).map_err(|_| e)?;
        }
    }

    // Build the recipient URL with the key fragment so the browser can decrypt.
    let fragment = format!("k={}&iv={}", b64u_encode(&key), b64u_encode(&iv));
    let recipient_url = format!("{}/en/s/{}#{}", url, resp.id, fragment);

    // Optional email link — detect lang from $LANG env; non-fatal on failure.
    let mut email_warning: Option<String> = None;
    if let Some(ref to) = args.to {
        let lang_env = std::env::var("LANG").unwrap_or_default();
        let lang_code = if lang_env.to_lowercase().starts_with("fr") {
            "fr"
        } else {
            "en"
        };
        if let Err(e) = client.email_link(&resp.id, &recipient_url, to, lang_code) {
            email_warning = Some(format!("failed to email: {e}"));
        }
    }

    // Compute absolute expiresAt for --json (ISO 8601 via chrono).
    let expires_seconds: i64 = match args.expires.as_str() {
        "1h" => 60 * 60,
        "24h" => 60 * 60 * 24,
        "7d" => 60 * 60 * 24 * 7,
        "30d" => 60 * 60 * 24 * 30,
        _ => unreachable!("clap value_parser already constrained this"),
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| CliError::Generic(e.to_string()))?
        .as_secs() as i64;
    let expires_at_iso = chrono::DateTime::from_timestamp(now + expires_seconds, 0)
        .ok_or_else(|| CliError::Generic("expiresAt overflow".to_string()))?
        .to_rfc3339();

    // Output.
    if args.plain {
        println!("{}", recipient_url);
        // Always emit email warning to stderr so it is visible regardless of output mode.
        if let Some(ref w) = email_warning {
            eprintln!("{}", theme.error(&format!("warning: {w}")));
        }
    } else if args.json {
        let mut body = serde_json::json!({
            "id": resp.id,
            "url": recipient_url,
            "expiresAt": expires_at_iso,
        });
        // Machine consumers can detect email failure via this field.
        if let Some(ref w) = email_warning {
            body["emailWarning"] = serde_json::Value::String(w.clone());
        }
        println!(
            "{}",
            serde_json::to_string(&body).map_err(|e| CliError::Generic(e.to_string()))?
        );
        // Also emit to stderr so the warning is visible even when stdout is piped.
        if let Some(ref w) = email_warning {
            eprintln!("warning: {w}");
        }
    } else {
        println!("{} Share created", theme.success("✓"));
        println!("  {} {}", theme.accent("URL:"), recipient_url);
        println!("  {} {}", theme.accent("Expires:"), args.expires);
        println!("  {} {}/{}", theme.accent("Opens:"), 0, args.opens);
        println!("  {} {}", theme.accent("Id:"), theme.muted(&resp.id));
        if let Some(ref to) = args.to {
            if email_warning.is_none() {
                println!("  {}", theme.muted(&format!("(link emailed to {to})")));
            }
        }
        if let Some(ref w) = email_warning {
            eprintln!("  {}", theme.error(&format!("({w})")));
        }
    }

    Ok(())
}

/// Email plausibility check — matches the server-side rule:
///   /^[^\s@]+@[^\s@]+\.[^\s@]+$/ with a 254-char total length cap (RFC 5321).
///
/// Equivalent logic, hand-coded to avoid pulling in the `regex` crate (~600 KB):
///   - No whitespace anywhere in the address.
///   - Exactly one `@`; non-empty local part before it.
///   - Domain part contains a `.`; no leading/trailing dot; no `@` in domain.
///   - Total length ≤ 254 characters.
fn looks_like_email(s: &str) -> bool {
    // Length cap matching server (RFC 5321 maximum).
    if s.len() > 254 {
        return false;
    }
    // No whitespace allowed anywhere.
    if s.chars().any(|c| c.is_whitespace()) {
        return false;
    }
    // Exactly one '@'; split into local and domain.
    let at_count = s.chars().filter(|&c| c == '@').count();
    if at_count != 1 {
        return false;
    }
    let at = s.find('@').unwrap();
    let local = &s[..at];
    let domain = &s[at + 1..];
    // Local part must be non-empty and contain no '@'.
    if local.is_empty() {
        return false;
    }
    // Domain must be non-empty, contain a dot, no leading/trailing dot, no '@'.
    if domain.is_empty() || domain.contains('@') {
        return false;
    }
    if !domain.contains('.') || domain.starts_with('.') || domain.ends_with('.') {
        return false;
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn looks_like_email_valid() {
        assert!(looks_like_email("user@example.com"));
        assert!(looks_like_email("user+tag@sub.domain.org"));
        assert!(looks_like_email("a@b.co"));
    }

    #[test]
    fn looks_like_email_invalid() {
        assert!(!looks_like_email("notanemail"));
        assert!(!looks_like_email("@nodomain.com"));
        assert!(!looks_like_email("user@"));
        assert!(!looks_like_email("user@.com"));
        assert!(!looks_like_email("user@nodot"));
        assert!(!looks_like_email("user@ends."));
    }

    #[test]
    fn looks_like_email_rejects_whitespace() {
        // Server regex: /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        assert!(!looks_like_email("us er@example.com"));
        assert!(!looks_like_email("user@ex ample.com"));
        assert!(!looks_like_email("user @example.com"));
    }

    #[test]
    fn looks_like_email_rejects_multiple_at() {
        assert!(!looks_like_email("a@b@c.com"));
    }

    #[test]
    fn looks_like_email_rejects_over_254_chars() {
        // 255-char address: local(64) + '@' + domain(190) = 255
        let long = format!("{}@{}.com", "a".repeat(64), "b".repeat(187));
        assert_eq!(long.len(), 256);
        assert!(!looks_like_email(&long));
    }

    #[test]
    fn looks_like_email_accepts_exactly_254_chars() {
        // 254-char address should be accepted.
        let addr = format!("{}@{}.com", "a".repeat(63), "b".repeat(186));
        assert_eq!(addr.len(), 254);
        assert!(looks_like_email(&addr));
    }
}
