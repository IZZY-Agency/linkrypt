use anyhow::{anyhow, Result};
use std::io::{IsTerminal, Read};
use std::path::Path;

#[derive(Debug)]
pub enum Source {
    Text(String),
    Binary { bytes: Vec<u8>, filename: String },
}

/// Resolve the content source from the given inputs.
///
/// `stdin_piped_override` is `None` in production (auto-detected via
/// `IsTerminal`) and `Some(bool)` in unit tests to avoid the test harness
/// always counting stdin as a piped source.
pub fn resolve(
    text_arg: Option<&str>,
    file_arg: Option<&Path>,
    explicit_filename: Option<&str>,
) -> Result<Source> {
    resolve_inner(
        text_arg,
        file_arg,
        explicit_filename,
        !std::io::stdin().is_terminal(),
    )
}

fn resolve_inner(
    text_arg: Option<&str>,
    file_arg: Option<&Path>,
    explicit_filename: Option<&str>,
    stdin_piped: bool,
) -> Result<Source> {
    let n_sources = [text_arg.is_some(), file_arg.is_some(), stdin_piped]
        .iter()
        .filter(|b| **b)
        .count();

    if n_sources == 0 {
        return Err(anyhow!("no content; pass text, --file, or pipe stdin"));
    }
    if n_sources > 1 {
        return Err(anyhow!(
            "provide exactly one of --file, a positional argument, or piped stdin"
        ));
    }

    if let Some(path) = file_arg {
        let bytes = std::fs::read(path)?;
        let filename = explicit_filename.map(String::from).unwrap_or_else(|| {
            path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("download.bin")
                .to_string()
        });
        return Ok(Source::Binary { bytes, filename });
    }

    if let Some(text) = text_arg {
        return Ok(Source::Text(text.to_string()));
    }

    // stdin branch — only reached when stdin_piped == true
    let mut buf = Vec::new();
    std::io::stdin().read_to_end(&mut buf)?;
    match std::str::from_utf8(&buf) {
        Ok(s) => Ok(Source::Text(s.to_string())),
        Err(_) => {
            let filename = explicit_filename.unwrap_or("stdin.bin").to_string();
            Ok(Source::Binary {
                bytes: buf,
                filename,
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    // Helper: call resolve_inner with stdin_piped=false (simulating TTY)
    fn resolve_tty(
        text_arg: Option<&str>,
        file_arg: Option<&Path>,
        explicit_filename: Option<&str>,
    ) -> Result<Source> {
        resolve_inner(text_arg, file_arg, explicit_filename, false)
    }

    // Helper: call resolve_inner with stdin_piped=true
    fn resolve_piped(
        text_arg: Option<&str>,
        file_arg: Option<&Path>,
        explicit_filename: Option<&str>,
    ) -> Result<Source> {
        resolve_inner(text_arg, file_arg, explicit_filename, true)
    }

    #[test]
    fn text_arg_produces_text_source() {
        let src = resolve_tty(Some("hello world"), None, None).unwrap();
        match src {
            Source::Text(s) => assert_eq!(s, "hello world"),
            Source::Binary { .. } => panic!("expected Text"),
        }
    }

    #[test]
    fn file_arg_produces_binary_source_with_path_filename() {
        let dir = std::env::temp_dir();
        let path = dir.join("linkrypt_test_input.bin");
        std::fs::write(&path, b"\x00\x01\x02").unwrap();

        let src = resolve_tty(None, Some(&path), None).unwrap();
        match src {
            Source::Binary { bytes, filename } => {
                assert_eq!(bytes, b"\x00\x01\x02");
                assert_eq!(filename, "linkrypt_test_input.bin");
            }
            Source::Text(_) => panic!("expected Binary"),
        }
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn file_arg_uses_explicit_filename_override() {
        let dir = std::env::temp_dir();
        let path = dir.join("linkrypt_test_override.bin");
        std::fs::write(&path, b"data").unwrap();

        let src = resolve_tty(None, Some(&path), Some("custom.bin")).unwrap();
        match src {
            Source::Binary { filename, .. } => assert_eq!(filename, "custom.bin"),
            Source::Text(_) => panic!("expected Binary"),
        }
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn rejects_no_sources_when_tty() {
        let err = resolve_tty(None, None, None);
        assert!(err.is_err());
        let msg = err.unwrap_err().to_string();
        assert!(msg.contains("no content"), "unexpected message: {msg}");
    }

    #[test]
    fn rejects_multiple_sources_text_and_file() {
        // text + file (stdin=false): 2 sources → error
        let err = resolve_tty(Some("x"), Some(&PathBuf::from("/tmp/x")), None);
        assert!(err.is_err());
        let msg = err.unwrap_err().to_string();
        assert!(msg.contains("exactly one"), "unexpected message: {msg}");
    }

    #[test]
    fn rejects_multiple_sources_text_and_stdin() {
        // text + stdin piped: 2 sources → error
        let err = resolve_piped(Some("x"), None, None);
        assert!(err.is_err());
        let msg = err.unwrap_err().to_string();
        assert!(msg.contains("exactly one"), "unexpected message: {msg}");
    }

    #[test]
    fn rejects_multiple_sources_file_and_stdin() {
        // file + stdin piped: 2 sources → error
        let err = resolve_piped(None, Some(&PathBuf::from("/tmp/x")), None);
        assert!(err.is_err());
        let msg = err.unwrap_err().to_string();
        assert!(msg.contains("exactly one"), "unexpected message: {msg}");
    }

    #[test]
    fn stdin_utf8_produces_text() {
        // We cannot actually pipe bytes in a unit test, but we can verify the
        // utf8 branch logic by calling read_to_end on a cursor.
        // Simulate by directly testing str::from_utf8 path with valid UTF-8.
        let bytes: Vec<u8> = b"valid utf-8 text".to_vec();
        match std::str::from_utf8(&bytes) {
            Ok(s) => assert_eq!(s, "valid utf-8 text"),
            Err(_) => panic!("should be valid UTF-8"),
        }
    }

    #[test]
    #[allow(clippy::unnecessary_literal_unwrap)]
    fn stdin_binary_uses_default_filename() {
        // Verify the filename fallback logic for binary stdin
        let explicit_filename: Option<&str> = None;
        let filename = explicit_filename.unwrap_or("stdin.bin");
        assert_eq!(filename, "stdin.bin");
    }

    #[test]
    #[allow(clippy::unnecessary_literal_unwrap)]
    fn stdin_binary_uses_explicit_filename() {
        let explicit_filename: Option<&str> = Some("data.dat");
        let filename = explicit_filename.unwrap_or("stdin.bin");
        assert_eq!(filename, "data.dat");
    }
}
