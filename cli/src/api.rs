use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::time::Instant;

/// Strip the query string from a URL before logging it.
///
/// R2 pre-signed PUT URLs carry short-lived AWS SigV4 credentials in the
/// query string. Printing them on stderr (even with `--verbose`) could expose
/// secrets in CI logs or shell history. Regular API URLs never have secrets in
/// the query string, so this helper is applied only to the R2 PUT path.
fn redact_url(url: &str) -> Cow<'_, str> {
    match url.find('?') {
        None => Cow::Borrowed(url),
        Some(q) => Cow::Owned(format!("{}?[REDACTED]", &url[..q])),
    }
}

pub struct Client {
    pub base_url: String,
    pub token: String,
    pub verbose: bool,
    agent: ureq::Agent,
}

// The server expects camelCase keys (same contract as /api/shares).
// Without the rename, snake_case Rust fields would serialize as
// `expires_in` / `max_opens`, which the server rejects as a bad body.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateShareReq<'a> {
    pub r#type: &'a str,
    pub size: usize,
    pub expires_in: &'a str, // → "expiresIn"
    pub max_opens: u32,      // → "maxOpens"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filename: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recipient_email: Option<&'a str>, // → "recipientEmail"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notify_on_open: Option<bool>, // → "notifyOnOpen"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub passphrase_salt: Option<&'a str>, // → "passphraseSalt"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub passphrase_hash: Option<&'a str>, // → "passphraseHash"
}

#[derive(Debug, Deserialize)]
pub struct CreateShareResp {
    pub id: String,
    #[serde(rename = "uploadUrl")]
    pub upload_url: Option<String>,
}

impl Client {
    pub fn new(base_url: impl Into<String>, token: impl Into<String>, verbose: bool) -> Self {
        // ureq 3: keep non-2xx responses as Ok(...) (http_status_as_error
        // false) so handlers can still read the server's JSON error bodies;
        // status handling is centralized in handle/handle_empty/status_err.
        let agent = ureq::config::Config::builder()
            .timeout_global(Some(std::time::Duration::from_secs(30)))
            .http_status_as_error(false)
            .build()
            .new_agent();
        Self {
            base_url: base_url.into(),
            token: token.into(),
            verbose,
            agent,
        }
    }

    fn auth_header(&self) -> String {
        format!("Bearer {}", self.token)
    }

    fn log(&self, method: &str, url: &str, status: Option<u16>, elapsed_ms: u128) {
        if self.verbose {
            match status {
                Some(s) => eprintln!("» {method} {url} → {s} ({elapsed_ms}ms)"),
                None => eprintln!("» {method} {url} → ERR ({elapsed_ms}ms)"),
            }
        }
    }

    pub fn create_share(&self, req: &CreateShareReq) -> Result<CreateShareResp> {
        let url = format!("{}/api/cli/shares", self.base_url);
        let t = Instant::now();
        let resp = self
            .agent
            .post(&url)
            .header("authorization", &self.auth_header())
            .send_json(serde_json::to_value(req)?);
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("POST", &url, status, t.elapsed().as_millis());
        self.handle::<CreateShareResp>(resp, "create share")
    }

    pub fn finalize_text(&self, id: &str, ciphertext: &[u8]) -> Result<()> {
        let url = format!("{}/api/cli/shares/{}/finalize", self.base_url, id);
        let t = Instant::now();
        let resp = self
            .agent
            .post(&url)
            .header("authorization", &self.auth_header())
            .header("content-type", "application/octet-stream")
            .send(ciphertext);
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("POST", &url, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "finalize text")
            .map(|_| ())
    }

    pub fn finalize_file(&self, id: &str) -> Result<()> {
        let url = format!("{}/api/cli/shares/{}/finalize", self.base_url, id);
        let t = Instant::now();
        let resp = self
            .agent
            .post(&url)
            .header("authorization", &self.auth_header())
            .header("content-type", "application/json")
            .send("{}");
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("POST", &url, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "finalize file")
            .map(|_| ())
    }

    #[allow(dead_code)]
    pub fn put_r2(&self, upload_url: &str, ciphertext: &[u8]) -> Result<()> {
        self.put_r2_with_progress(upload_url, ciphertext, None::<fn(usize)>)
    }

    /// PUT ciphertext to an R2 pre-signed URL.
    ///
    /// `ureq` does not expose a streaming-with-callback API, so true per-byte
    /// progress is not possible. The two-tick pattern (call `cb(0)` before the
    /// PUT and `cb(total)` after) is enough for the progress bar to appear and
    /// complete. The 100 MiB cap keeps the whole payload in memory anyway, so
    /// this is acceptable until uploads are chunked.
    pub fn put_r2_with_progress(
        &self,
        upload_url: &str,
        ciphertext: &[u8],
        on_progress: Option<impl Fn(usize)>,
    ) -> Result<()> {
        if let Some(cb) = on_progress.as_ref() {
            cb(0);
        }
        let t = Instant::now();
        let resp = self
            .agent
            .put(upload_url)
            .header("content-type", "application/octet-stream")
            .send(ciphertext);
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log(
            "PUT",
            &redact_url(upload_url),
            status,
            t.elapsed().as_millis(),
        );
        match resp {
            Ok(r) if r.status().is_success() => {
                if let Some(cb) = on_progress.as_ref() {
                    cb(ciphertext.len());
                }
                Ok(())
            }
            Ok(r) => Err(status_err(r, "r2 PUT")),
            Err(e) => Err(anyhow!("network: {e} (r2 PUT)")),
        }
    }

    pub fn email_link(&self, id: &str, url: &str, recipient: &str, lang: &str) -> Result<()> {
        let endpoint = format!("{}/api/cli/shares/{}/email-link", self.base_url, id);
        let body = serde_json::json!({
            "url": url,
            "recipientEmail": recipient,
            "lang": lang,
        });
        let t = Instant::now();
        let resp = self
            .agent
            .post(&endpoint)
            .header("authorization", &self.auth_header())
            .send_json(body);
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("POST", &endpoint, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "email link")
            .map(|_| ())
    }

    pub fn whoami(&self) -> Result<serde_json::Value> {
        // Authenticated probe used by `linkrypt login` to validate a
        // freshly pasted token.
        let url = format!("{}/api/cli/whoami", self.base_url);
        let t = Instant::now();
        let resp = self
            .agent
            .get(&url)
            .header("authorization", &self.auth_header())
            .call();
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("GET", &url, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "whoami")
    }

    pub fn healthz(&self) -> Result<serde_json::Value> {
        let url = format!("{}/api/healthz", self.base_url);
        let t = Instant::now();
        let resp = self.agent.get(&url).call();
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("GET", &url, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "healthz")
    }

    pub fn list_shares(&self) -> Result<serde_json::Value> {
        let url = format!("{}/api/cli/list", self.base_url);
        let t = Instant::now();
        let resp = self
            .agent
            .get(&url)
            .header("authorization", &self.auth_header())
            .call();
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("GET", &url, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "list shares")
    }

    pub fn revoke_share(&self, id: &str) -> Result<()> {
        // /api/cli/revoke/:id returns 204 No Content; parsing JSON from an
        // empty body would error, so use the empty-body handler.
        let url = format!(
            "{}/api/cli/revoke/{}",
            self.base_url,
            urlencoding::encode(id)
        );
        let t = Instant::now();
        let resp = self
            .agent
            .delete(&url)
            .header("authorization", &self.auth_header())
            .call();
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("DELETE", &url, status, t.elapsed().as_millis());
        self.handle_empty(resp, "revoke share")
    }

    pub fn audit(&self, limit: Option<u32>) -> Result<serde_json::Value> {
        let url = match limit {
            Some(n) => format!("{}/api/cli/audit?limit={}", self.base_url, n),
            None => format!("{}/api/cli/audit", self.base_url),
        };
        let t = Instant::now();
        let resp = self
            .agent
            .get(&url)
            .header("authorization", &self.auth_header())
            .call();
        let status = match &resp {
            Ok(r) => Some(r.status().as_u16()),
            Err(_) => None,
        };
        self.log("GET", &url, status, t.elapsed().as_millis());
        self.handle::<serde_json::Value>(resp, "audit")
    }

    fn handle<T: serde::de::DeserializeOwned>(
        &self,
        resp: Result<ureq::http::Response<ureq::Body>, ureq::Error>,
        ctx: &str,
    ) -> Result<T> {
        match resp {
            Ok(r) if r.status().is_success() => r
                .into_body()
                .read_json::<T>()
                .with_context(|| ctx.to_string()),
            Ok(r) => Err(status_err(r, ctx)),
            Err(e) => Err(anyhow!("network: {e} ({ctx})")),
        }
    }

    fn handle_empty(
        &self,
        resp: Result<ureq::http::Response<ureq::Body>, ureq::Error>,
        ctx: &str,
    ) -> Result<()> {
        match resp {
            Ok(r) if r.status().is_success() => Ok(()),
            Ok(r) => Err(status_err(r, ctx)),
            Err(e) => Err(anyhow!("network: {e} ({ctx})")),
        }
    }
}

/// Turn a non-2xx response into the CLI's error message contract.
/// The "unauthorized — " / "forbidden — " prefixes are load-bearing:
/// error.rs `From<anyhow::Error> for CliError` routes on them for exit
/// codes, and login.rs distinguishes token rejection from server faults.
fn status_err(r: ureq::http::Response<ureq::Body>, ctx: &str) -> anyhow::Error {
    let code = r.status().as_u16();
    let msg = r.into_body().read_to_string().unwrap_or_default();
    match code {
        401 => anyhow!("unauthorized — check LINKRYPT_API_TOKEN ({ctx})"),
        403 => anyhow!("forbidden — {} ({ctx})", msg),
        _ => anyhow!("{}: {} ({ctx})", code, msg),
    }
}
