use anyhow::{anyhow, Result};

use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};

// POSIX permission bits don't exist on Windows. The Unix-only file
// protection here is replaced on Windows by relying on the default NTFS
// ACLs of %APPDATA%, which are user-scoped by default — equivalent
// security boundary for the threat model (other users on the same machine
// shouldn't read the API token).
#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

pub const DEFAULT_API_URL: &str = "https://linkrypt.sh";

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub url: String,
    pub token: String,
}

// ── Named environment profiles ─────────────────────────────
//
// Multi-profile config shape (soft-migrates the legacy single {url,token}
// on read; persisted in the new shape on the next write):
//
//   { "current": "staging",
//     "profiles": { "staging": { "url": "...", "token": "lk_..." }, ... } }

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Profile {
    pub url: String,
    pub token: String,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub struct MultiConfig {
    pub current: String,
    pub profiles: std::collections::BTreeMap<String, Profile>,
}

impl MultiConfig {
    /// Parse a config file body: the multi-profile shape, or (soft
    /// migration) the legacy single `{url, token}` shape mapped to
    /// `current: "default"`.
    pub fn parse(s: &str) -> Result<MultiConfig> {
        // Invariants: a usable multi config
        // has a non-empty profile set and a non-empty `current` that exists
        // in it. A doc that fails these falls through to the legacy branch —
        // so a mixed legacy/multi file migrates its {url,token} instead of
        // silently discarding it.
        if let Ok(multi) = serde_json::from_str::<MultiConfig>(s) {
            if !multi.current.is_empty()
                && !multi.profiles.is_empty()
                && multi.profiles.contains_key(&multi.current)
            {
                return Ok(multi);
            }
        }
        if let Ok(legacy) = serde_json::from_str::<Config>(s) {
            let mut profiles = std::collections::BTreeMap::new();
            profiles.insert(
                "default".to_string(),
                Profile {
                    url: legacy.url,
                    token: legacy.token,
                },
            );
            return Ok(MultiConfig {
                current: "default".to_string(),
                profiles,
            });
        }
        Err(anyhow!(
            "unrecognized config format (expected profiles or legacy {{url, token}})"
        ))
    }

    pub fn current_profile(&self) -> Result<&Profile> {
        self.profiles.get(&self.current).ok_or_else(|| {
            anyhow!(
                "current profile '{}' not found — run '{} env list'",
                self.current,
                BIN_NAME
            )
        })
    }

    /// Point `current` at an existing profile.
    pub fn switch(&mut self, name: &str) -> Result<()> {
        if !self.profiles.contains_key(name) {
            return Err(anyhow!(
                "no profile named '{name}' — run '{BIN_NAME} env list'"
            ));
        }
        self.current = name.to_string();
        Ok(())
    }

    /// Add (or replace) a profile and make it current.
    pub fn add(&mut self, name: &str, url: &str, token: &str) {
        self.profiles.insert(
            name.to_string(),
            Profile {
                url: url.to_string(),
                token: token.to_string(),
            },
        );
        self.current = name.to_string();
    }

    /// Remove a profile. Refuses to remove the CURRENT profile so the
    /// config can never end up pointing at nothing — switch first.
    pub fn remove(&mut self, name: &str) -> Result<()> {
        if !self.profiles.contains_key(name) {
            return Err(anyhow!(
                "no profile named '{name}' — run '{BIN_NAME} env list'"
            ));
        }
        if name == self.current {
            return Err(anyhow!(
                "'{name}' is the current profile — switch first with '{BIN_NAME} env use <other>'"
            ));
        }
        self.profiles.remove(name);
        Ok(())
    }
}

/// Read + parse the config file as MultiConfig (soft-migrating the
/// legacy shape). Same Unix permission hardening as `read_config`.
pub fn read_multi_config(path: &Path) -> Result<MultiConfig> {
    #[cfg(unix)]
    {
        let meta = std::fs::metadata(path)?;
        let mode = meta.permissions().mode() & 0o777;
        if mode & 0o077 != 0 {
            return Err(anyhow!(
                "refusing to read config: permissions {:04o} are too broad \
                 (group/other bits set). Run: chmod 600 {}",
                mode,
                path.display()
            ));
        }
    }
    let s = std::fs::read_to_string(path)?;
    MultiConfig::parse(&s)
}

// Name of the per-user config directory.
const CONFIG_DIR_NAME: &str = "linkrypt";

// Binary name for error messages. `env!("CARGO_BIN_NAME")` is only set
// when compiling a `[[bin]]` target, so it's unavailable in the library
// crate — hardcode it here instead.
const BIN_NAME: &str = "linkrypt";

/// Returns the canonical config file path for the current OS.
///
/// macOS: `~/Library/Application Support/linkrypt/config.json`
/// Linux: `~/.config/linkrypt/config.json`  (XDG convention)
///
/// The `directories` crate follows OS conventions, so on macOS this will
/// be `~/Library/Application Support/linkrypt/` instead.
pub fn config_path() -> Result<PathBuf> {
    let dirs = ProjectDirs::from("", "", CONFIG_DIR_NAME)
        .ok_or_else(|| anyhow!("could not resolve config dir"))?;
    Ok(dirs.config_dir().join("config.json"))
}

/// Write `bytes` to `path` atomically.
///
/// On Unix the temp file is created with `create_new` + `mode(0o600)` so
/// the restrictive permissions are set before any data lands on disk
/// and no other user can open it in the meantime. On Windows we rely on
/// the default NTFS ACLs of %APPDATA% (user-scoped by default)
/// instead — Windows OpenOptions
/// has no `mode()` and the platform-equivalent ACL APIs are heavyweight
/// for the same threat model. A `rename(2)`/`MoveFileEx` then makes the
/// write atomic.
pub fn write_atomic_0600(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // Derive the temp path next to the destination.
    let tmp = path.with_extension("json.tmp");
    {
        let mut opts = OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        opts.mode(0o600);
        let mut f = opts.open(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Read and deserialise the config file at `path`.
///
/// On Unix: refuses to proceed if the file's permission bits allow group
/// or other read/write/execute access (any bit in the lower six set).
/// Prevents accidental exposure of the API token when the config was
/// created with a permissive umask.
///
/// On Windows: POSIX mode bits don't exist; the file is implicitly
/// user-scoped via %APPDATA%'s default ACLs (see `write_atomic_0600`
/// for the equivalent-threat-model rationale). The permission check is
/// a no-op on Windows.
#[allow(dead_code)]
pub fn read_config(path: &Path) -> Result<Config> {
    #[cfg(unix)]
    {
        let meta = std::fs::metadata(path)?;
        let mode = meta.permissions().mode() & 0o777;
        if mode & 0o077 != 0 {
            return Err(anyhow!(
                "refusing to read config: permissions {:04o} are too broad \
                 (group/other bits set). Run: chmod 600 {}",
                mode,
                path.display()
            ));
        }
    }
    let s = std::fs::read_to_string(path)?;
    Ok(serde_json::from_str(&s)?)
}

/// Resolve the API token and base URL from (in precedence order):
///
/// 1. `LINKRYPT_API_TOKEN` environment variable (highest priority).
/// 2. The on-disk config file (`~/.config/linkrypt/config.json` / `~/Library/…`).
///
/// `cli_url` overrides the URL from any source when supplied.
#[allow(dead_code)]
pub fn resolve_token_and_url(cli_url: Option<&str>) -> Result<(String, String)> {
    // 1. env var wins for token
    if let Ok(token) = std::env::var("LINKRYPT_API_TOKEN") {
        let url = cli_url
            .map(String::from)
            .or_else(|| std::env::var("LINKRYPT_API_URL").ok())
            .unwrap_or_else(|| DEFAULT_API_URL.to_string());
        return Ok((token, url.trim_end_matches('/').to_string()));
    }
    // 2. config file (multi-profile; legacy single-config soft-migrates)
    let path = config_path()?;
    if path.exists() {
        let cfg = read_multi_config(&path)?;
        let profile = cfg.current_profile()?;
        let url = cli_url.unwrap_or(&profile.url).to_string();
        return Ok((profile.token.clone(), url.trim_end_matches('/').to_string()));
    }
    Err(anyhow!(
        "not logged in — run '{} login' or set LINKRYPT_API_TOKEN",
        BIN_NAME
    ))
}

/// Validate that `url` uses HTTPS.
///
/// Uses `url::Url::parse` for an exact host match rather than a string
/// prefix check. A prefix check like `starts_with("http://localhost")` would
/// also accept `http://localhost.evil.com`.
///
/// HTTP is allowed only when the `LINKRYPT_ALLOW_HTTP` env var is set **and**
/// the host is exactly `localhost`, `127.0.0.1`, or `::1`.
pub fn validate_https(url: &str) -> Result<()> {
    let parsed = url::Url::parse(url).map_err(|_| anyhow!("invalid URL: {url}"))?;

    // Require origin-only: no path beyond "/", no query, no fragment.
    // A URL like https://example.com/some/path?x would produce broken
    // API endpoints such as /some/path?x/api/cli/shares.
    let path = parsed.path();
    if path != "/" && !path.is_empty() {
        return Err(anyhow!(
            "base URL must be the origin only (no path/query/fragment): {url}"
        ));
    }
    if parsed.query().is_some() {
        return Err(anyhow!(
            "base URL must be the origin only (no path/query/fragment): {url}"
        ));
    }
    if parsed.fragment().is_some() {
        return Err(anyhow!(
            "base URL must be the origin only (no path/query/fragment): {url}"
        ));
    }

    // Reject embedded credentials: profile URLs are printed by `env list`,
    // so userinfo must never be storable.
    if !parsed.username().is_empty() || parsed.password().is_some() {
        return Err(anyhow!(
            "base URL must not contain credentials (user:pass@): {url}"
        ));
    }

    if parsed.scheme() == "https" {
        return Ok(());
    }
    if parsed.scheme() == "http"
        && std::env::var_os("LINKRYPT_ALLOW_HTTP").is_some()
        && matches!(
            parsed.host_str(),
            Some("localhost") | Some("127.0.0.1") | Some("::1")
        )
    {
        return Ok(());
    }
    Err(anyhow!(
        "base URL must use https:// \
         (set LINKRYPT_ALLOW_HTTP=1 and use http://localhost for local dev)"
    ))
}

/// URL-only resolution for UNAUTHENTICATED commands (healthz): explicit
/// CLI/env URL > current profile's URL > built-in default. Pure so it is
/// testable; `resolve_url_for_unauthenticated` wires the config file in.
pub fn resolve_url_only(cli_url: Option<&str>, cfg: Option<&MultiConfig>) -> String {
    if let Some(u) = cli_url {
        return u.trim_end_matches('/').to_string();
    }
    if let Some(cfg) = cfg {
        if let Ok(p) = cfg.current_profile() {
            return p.url.trim_end_matches('/').to_string();
        }
    }
    DEFAULT_API_URL.to_string()
}

/// Load-and-resolve wrapper around `resolve_url_only`: a bare `healthz`
/// after `env use <name>` must probe that profile, not the built-in
/// default. A missing or unreadable config silently falls back — healthz
/// must work pre-login.
pub fn resolve_url_for_unauthenticated(cli_url: Option<&str>) -> String {
    let cfg = config_path()
        .ok()
        .filter(|p| p.exists())
        .and_then(|p| read_multi_config(&p).ok());
    resolve_url_only(cli_url, cfg.as_ref())
}

/// Exclusive advisory lock for config mutations: an unlocked
/// read-modify-write would let two concurrent CLI invocations lose one
/// of the updates. Held across read + mutate + write.
///
/// Implementation: O_EXCL creation of `config.json.lock`; the guard
/// removes it on drop. A crash can strand the lock, so a lock file
/// older than STALE_AFTER is broken and re-acquired.
#[derive(Debug)]
pub struct ConfigLock {
    path: PathBuf,
}

impl ConfigLock {
    const STALE_AFTER: std::time::Duration = std::time::Duration::from_secs(60);

    pub fn acquire(config_path: &Path) -> Result<ConfigLock> {
        let path = config_path.with_extension("json.lock");
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        for attempt in 0..2 {
            match OpenOptions::new().write(true).create_new(true).open(&path) {
                Ok(_) => return Ok(ConfigLock { path }),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt == 0 => {
                    // Break stale locks from crashed processes.
                    let stale = std::fs::metadata(&path)
                        .and_then(|m| m.modified())
                        .ok()
                        .and_then(|t| t.elapsed().ok())
                        .is_some_and(|age| age > Self::STALE_AFTER);
                    if stale {
                        let _ = std::fs::remove_file(&path);
                        continue;
                    }
                    return Err(anyhow!(
                        "config is locked by another {BIN_NAME} process (remove {} if stale)",
                        path.display()
                    ));
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                    return Err(anyhow!(
                        "config is locked by another {BIN_NAME} process (remove {} if stale)",
                        path.display()
                    ));
                }
                Err(e) => return Err(e.into()),
            }
        }
        unreachable!("acquire loop covers both attempts");
    }
}

impl Drop for ConfigLock {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

// POSIX mode-bit tests are Unix-only — they assert behaviors that don't
// exist on Windows (where the equivalent threat model is handled by
// %APPDATA% ACLs, not file permission bits).
#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use tempfile::TempDir;

    #[test]
    fn atomic_write_creates_mode_600_file() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("config.json");
        write_atomic_0600(&path, b"hello").unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        assert_eq!(std::fs::read(&path).unwrap(), b"hello");
    }

    #[test]
    fn read_rejects_too_permissive_mode() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("config.json");
        std::fs::write(&path, b"{}").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        let err = read_config(&path).unwrap_err();
        assert!(err.to_string().contains("permissions"));
    }
}

// On Windows: just verify the file roundtrips. Mode-bit assertions are
// the Unix module's job; here we exercise the cfg-gated code paths
// (no .mode() in OpenOptions, no permission check in read_config) so the
// CI Windows builds gain at least minimal coverage.
#[cfg(all(test, windows))]
mod tests_windows {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn atomic_write_roundtrips_on_windows() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("config.json");
        write_atomic_0600(&path, b"hello").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"hello");
    }

    #[test]
    fn read_accepts_any_permissions_on_windows() {
        // On Windows there's no POSIX mode check; any file the process can
        // read should round-trip through read_config.
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("config.json");
        std::fs::write(&path, r#"{"url":"https://x","token":"t"}"#).unwrap();
        let cfg = read_config(&path).unwrap();
        assert_eq!(cfg.url, "https://x");
        assert_eq!(cfg.token, "t");
    }
}

#[cfg(test)]
mod validate_https_tests {
    use super::*;
    use std::sync::Mutex;

    // Serialize env-var mutations across threads to prevent races.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn accepts_https() {
        assert!(validate_https("https://example.com").is_ok());
    }

    #[test]
    fn rejects_http_by_default() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::remove_var("LINKRYPT_ALLOW_HTTP");
        assert!(validate_https("http://example.com").is_err());
    }

    #[test]
    fn rejects_lookalike_localhost() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("LINKRYPT_ALLOW_HTTP", "1");
        let result = validate_https("http://localhost.evil.com");
        std::env::remove_var("LINKRYPT_ALLOW_HTTP");
        assert!(result.is_err());
    }

    #[test]
    fn allows_real_localhost_with_flag() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("LINKRYPT_ALLOW_HTTP", "1");
        let r1 = validate_https("http://localhost:8787");
        let r2 = validate_https("http://127.0.0.1:8787");
        std::env::remove_var("LINKRYPT_ALLOW_HTTP");
        assert!(r1.is_ok());
        assert!(r2.is_ok());
    }

    #[test]
    fn rejects_url_with_path() {
        // A base URL with a non-root path would produce broken API endpoints.
        let err = validate_https("https://example.com/some/path").unwrap_err();
        assert!(err.to_string().contains("origin only"));
    }

    #[test]
    fn rejects_url_with_query() {
        let err = validate_https("https://example.com?x=1").unwrap_err();
        assert!(err.to_string().contains("origin only"));
    }

    #[test]
    fn accepts_https_origin_with_trailing_slash() {
        // "https://example.com/" — path is "/" which is allowed.
        assert!(validate_https("https://example.com/").is_ok());
    }
}

#[cfg(test)]
mod resolve_token_tests {
    use super::*;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn env_branch_trims_slash_from_url_not_token() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("LINKRYPT_API_TOKEN", "tok_abc");
        std::env::set_var("LINKRYPT_API_URL", "https://example.com/");
        let (token, url) = resolve_token_and_url(None).unwrap();
        std::env::remove_var("LINKRYPT_API_TOKEN");
        std::env::remove_var("LINKRYPT_API_URL");
        // Token must NOT have slash trimmed; URL trailing slash must be stripped.
        assert_eq!(token, "tok_abc");
        assert_eq!(url, "https://example.com");
    }
}

#[cfg(test)]
mod profile_tests {
    use super::*;

    const MULTI: &str = r#"{
      "current": "staging",
      "profiles": {
        "prod":    { "url": "https://linkrypt.sh", "token": "lk_prod" },
        "staging": { "url": "https://staging.example.com", "token": "lk_stg" }
      }
    }"#;

    #[test]
    fn parses_multi_profile_config() {
        let cfg = MultiConfig::parse(MULTI).unwrap();
        assert_eq!(cfg.current, "staging");
        assert_eq!(cfg.profiles.len(), 2);
        assert_eq!(cfg.profiles["prod"].token, "lk_prod");
    }

    #[test]
    fn migrates_legacy_single_config_to_default_profile() {
        let legacy = r#"{"url":"https://linkrypt.sh","token":"lk_old"}"#;
        let cfg = MultiConfig::parse(legacy).unwrap();
        assert_eq!(cfg.current, "default");
        assert_eq!(cfg.profiles.len(), 1);
        assert_eq!(cfg.profiles["default"].url, "https://linkrypt.sh");
        assert_eq!(cfg.profiles["default"].token, "lk_old");
    }

    #[test]
    fn rejects_garbage() {
        assert!(MultiConfig::parse("not json").is_err());
        assert!(MultiConfig::parse(r#"{"weird":true}"#).is_err());
    }

    #[test]
    fn current_profile_resolves_and_missing_current_errors() {
        let cfg = MultiConfig::parse(MULTI).unwrap();
        assert_eq!(cfg.current_profile().unwrap().token, "lk_stg");

        // parse() rejects a dangling `current` outright, so exercise
        // current_profile()'s own guard on a hand-built value.
        let mut profiles = std::collections::BTreeMap::new();
        profiles.insert(
            "a".to_string(),
            Profile {
                url: "https://x".into(),
                token: "t".into(),
            },
        );
        let cfg = MultiConfig {
            current: "gone".to_string(),
            profiles,
        };
        assert!(cfg.current_profile().is_err());
    }

    #[test]
    fn switch_profile_validates_name() {
        let mut cfg = MultiConfig::parse(MULTI).unwrap();
        cfg.switch("prod").unwrap();
        assert_eq!(cfg.current, "prod");
        assert!(cfg.switch("nope").is_err());
        assert_eq!(cfg.current, "prod"); // unchanged on error
    }

    #[test]
    fn add_profile_sets_current() {
        let mut cfg = MultiConfig::parse(MULTI).unwrap();
        cfg.add("dev", "http://localhost:8787", "lk_dev");
        assert_eq!(cfg.current, "dev");
        assert_eq!(cfg.profiles["dev"].url, "http://localhost:8787");
    }

    #[test]
    fn remove_refuses_current_and_removes_others() {
        let mut cfg = MultiConfig::parse(MULTI).unwrap();
        // current is "staging" — refuse
        assert!(cfg.remove("staging").is_err());
        assert!(cfg.profiles.contains_key("staging"));
        // non-current removes fine
        cfg.remove("prod").unwrap();
        assert!(!cfg.profiles.contains_key("prod"));
        // unknown name errors
        assert!(cfg.remove("ghost").is_err());
    }

    #[test]
    fn serializes_as_multi_shape() {
        let cfg = MultiConfig::parse(MULTI).unwrap();
        let s = serde_json::to_string(&cfg).unwrap();
        assert!(s.contains("\"current\""));
        assert!(s.contains("\"profiles\""));
    }
}

#[cfg(test)]
mod profile_edge_case_tests {
    use super::*;

    // Edge cases: parse invariants, credential-free URLs, URL precedence
    // for unauthenticated commands, and config locking.

    #[test]
    fn parse_rejects_multi_with_dangling_or_empty_invariants() {
        // dangling current
        assert!(MultiConfig::parse(
            r#"{"current":"gone","profiles":{"a":{"url":"https://x","token":"t"}}}"#
        )
        .is_err());
        // empty profiles map
        assert!(MultiConfig::parse(r#"{"current":"a","profiles":{}}"#).is_err());
        // empty current name
        assert!(MultiConfig::parse(
            r#"{"current":"","profiles":{"":{"url":"https://x","token":"t"}}}"#
        )
        .is_err());
    }

    #[test]
    fn parse_mixed_legacy_and_multi_fields_migrates_the_legacy_credentials() {
        // Mixed doc: the multi shape is invalid (empty profiles), so the
        // legacy {url,token} fields must win via migration rather than
        // being silently discarded.
        let mixed = r#"{"current":"","profiles":{},"url":"https://linkrypt.sh","token":"lk_old"}"#;
        let cfg = MultiConfig::parse(mixed).unwrap();
        assert_eq!(cfg.current, "default");
        assert_eq!(cfg.profiles["default"].token, "lk_old");
    }

    #[test]
    fn validate_https_rejects_userinfo() {
        // env list prints profile URLs; embedded credentials must never
        // be storable in the first place.
        assert!(validate_https("https://user:secret@example.com").is_err());
        assert!(validate_https("https://user@example.com").is_err());
    }

    #[test]
    fn resolve_url_only_prefers_cli_then_profile_then_default() {
        // Pure precedence helper for unauthenticated commands (healthz).
        let cfg = MultiConfig::parse(
            r#"{"current":"stg","profiles":{"stg":{"url":"https://staging.example.com","token":"t"}}}"#,
        )
        .unwrap();
        assert_eq!(
            resolve_url_only(Some("https://cli.example"), Some(&cfg)),
            "https://cli.example"
        );
        assert_eq!(
            resolve_url_only(None, Some(&cfg)),
            "https://staging.example.com"
        );
        assert_eq!(resolve_url_only(None, None), DEFAULT_API_URL);
    }

    #[test]
    fn config_lock_blocks_second_holder_and_breaks_stale_locks() {
        use tempfile::TempDir;
        let dir = TempDir::new().unwrap();
        let cfg_path = dir.path().join("config.json");
        let lock = ConfigLock::acquire(&cfg_path).unwrap();
        // Second acquisition while held → error mentioning another process.
        let err = ConfigLock::acquire(&cfg_path).unwrap_err().to_string();
        assert!(err.contains("another"), "got: {err}");
        drop(lock);
        // Released → acquirable again.
        let lock2 = ConfigLock::acquire(&cfg_path).unwrap();
        drop(lock2);
        // Stale lock (mtime in the past beyond threshold) is broken.
        let lock_path = cfg_path.with_extension("json.lock");
        std::fs::write(&lock_path, b"stale").unwrap();
        let old = std::time::SystemTime::now() - std::time::Duration::from_secs(120);
        let f = std::fs::File::options()
            .write(true)
            .open(&lock_path)
            .unwrap();
        f.set_modified(old).unwrap();
        drop(f);
        let lock3 = ConfigLock::acquire(&cfg_path);
        assert!(lock3.is_ok(), "stale lock must be broken");
    }
}
