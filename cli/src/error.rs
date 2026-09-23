use thiserror::Error;

#[derive(Debug, Error)]
pub enum CliError {
    #[error("{0}")]
    Generic(String), // exit 1
    #[error("{0}")]
    BadUsage(String), // exit 2
    #[error("unauthorized — {0}")]
    Unauthorized(String), // exit 3
    #[error("forbidden — {0}")]
    Forbidden(String), // exit 4
}

impl CliError {
    pub fn exit_code(&self) -> i32 {
        match self {
            CliError::Generic(_) => 1,
            CliError::BadUsage(_) => 2,
            CliError::Unauthorized(_) => 3,
            CliError::Forbidden(_) => 4,
        }
    }
}

pub type Result<T> = std::result::Result<T, CliError>;

/// Convert an anyhow error from the api module into a typed CliError.
///
/// The api module's `map_err` function produces human-readable messages that
/// start with "unauthorized — " or "forbidden — ". We route into the right
/// variant for the correct exit code, and strip the prefix from the payload
/// so the Display impl ("unauthorized — {0}") doesn't double-prefix:
///   api: "unauthorized — check LINKRYPT_API_TOKEN (ctx)"
///   CliError::Unauthorized("check LINKRYPT_API_TOKEN (ctx)")
///   Display: "unauthorized — check LINKRYPT_API_TOKEN (ctx)"  ✓
impl From<anyhow::Error> for CliError {
    fn from(e: anyhow::Error) -> Self {
        let msg = e.to_string();
        if let Some(rest) = msg.strip_prefix("unauthorized — ") {
            CliError::Unauthorized(rest.to_string())
        } else if msg.starts_with("unauthorized") {
            CliError::Unauthorized(msg)
        } else if let Some(rest) = msg.strip_prefix("forbidden — ") {
            CliError::Forbidden(rest.to_string())
        } else if msg.starts_with("forbidden") {
            CliError::Forbidden(msg)
        } else {
            CliError::Generic(msg)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::anyhow;

    #[test]
    fn unauthorized_no_double_prefix() {
        // api::map_err produces "unauthorized — check LINKRYPT_API_TOKEN (ctx)"
        let e: CliError = anyhow!("unauthorized — check LINKRYPT_API_TOKEN (whoami)").into();
        let display = e.to_string();
        assert!(
            !display.contains("unauthorized — unauthorized"),
            "double prefix detected: {display}"
        );
        assert!(display.contains("check LINKRYPT_API_TOKEN"));
        assert_eq!(e.exit_code(), 3);
    }

    #[test]
    fn forbidden_no_double_prefix() {
        let e: CliError = anyhow!("forbidden — not your share (revoke share)").into();
        let display = e.to_string();
        assert!(
            !display.contains("forbidden — forbidden"),
            "double prefix detected: {display}"
        );
        assert!(display.contains("not your share"));
        assert_eq!(e.exit_code(), 4);
    }

    #[test]
    fn generic_error_passes_through() {
        let e: CliError = anyhow!("network: connection refused (healthz)").into();
        assert_eq!(e.exit_code(), 1);
        assert!(e.to_string().contains("network"));
    }
}
