use linkrypt_cli::crypto::aes_encrypt;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// Cross-checks Rust encryption against the web client's TypeScript
/// decryption. That TypeScript lives alongside the server, outside this
/// crate; when it is not present (e.g. a standalone checkout of the CLI)
/// the test skips. The byte-for-byte WebCrypto vectors in tests/golden.rs
/// still run everywhere.
#[test]
fn rust_encrypt_then_node_decrypt_via_crypto_client_ts() {
    let web_crypto: PathBuf = [
        env!("CARGO_MANIFEST_DIR"),
        "..",
        "src",
        "lib",
        "crypto.client.ts",
    ]
    .iter()
    .collect();
    if !web_crypto.exists() {
        eprintln!(
            "skipped: {} not found (web client source is not part of this checkout)",
            web_crypto.display()
        );
        return;
    }

    let key = [0x42u8; 32];
    let iv = [0x13u8; 12];
    let pt = b"round-trip via the real crypto.client.ts";
    let ct = aes_encrypt(&key, &iv, pt).unwrap();

    let body = format!(
        r#"{{"key":"{}","iv":"{}","ct":"{}"}}"#,
        hex(&key),
        hex(&iv),
        hex(&ct)
    );

    let fixture: PathBuf = [
        env!("CARGO_MANIFEST_DIR"),
        "tests",
        "fixtures",
        "decrypt.mjs",
    ]
    .iter()
    .collect();
    assert!(fixture.exists(), "missing {}", fixture.display());

    // tsx is installed via `pnpm install` at the repo root.
    // Resolve it through `npx` so we don't depend on it being on PATH.
    let mut child = Command::new("npx")
        .args(["--yes", "tsx", fixture.to_str().unwrap()])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("npx must be on PATH (CI installs Node; locally: brew install node)");
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(body.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(
        out.status.success(),
        "tsx exited non-zero. stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );

    let pt_hex = String::from_utf8(out.stdout).unwrap();
    let pt_got: Vec<u8> = (0..pt_hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&pt_hex[i..i + 2], 16).unwrap())
        .collect();
    assert_eq!(pt_got, pt);
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
