// Crypto primitives shared by the commands and the golden-vector tests.

use aes_gcm::{aead::Aead, Aes256Gcm, KeyInit, Nonce};
use anyhow::{anyhow, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use pbkdf2::pbkdf2_hmac;
use rand::Rng as _; // rand 0.10: RngCore was renamed to Rng (rand_core 0.10)
use sha2::Sha256;

pub const PBKDF2_ITERATIONS: u32 = 600_000;
pub const AES_KEY_LEN: usize = 32;
pub const AES_IV_LEN: usize = 12;
pub const PBKDF2_SALT_LEN: usize = 16;
pub const PBKDF2_OUT_LEN: usize = 32;
/// Ciphertext size caps enforced by the server. The CLI pre-checks
/// plaintext + 16 (auth tag) before encrypting.
pub const MAX_TEXT_SIZE_CIPHERTEXT: usize = 256 * 1024;
pub const MAX_FILE_SIZE_CIPHERTEXT: usize = 100 * 1024 * 1024;

pub fn random_bytes(n: usize) -> Vec<u8> {
    let mut buf = vec![0u8; n];
    rand::rng().fill_bytes(&mut buf); // rand 0.10: thread_rng() -> rng()
    buf
}

pub fn aes_encrypt(key: &[u8; AES_KEY_LEN], iv: &[u8; AES_IV_LEN], pt: &[u8]) -> Result<Vec<u8>> {
    let cipher = Aes256Gcm::new(key.into());
    cipher
        .encrypt(&Nonce::from(*iv), pt)
        .map_err(|e| anyhow!("aes-gcm encrypt: {e}"))
}

#[allow(dead_code)]
pub fn aes_decrypt(key: &[u8; AES_KEY_LEN], iv: &[u8; AES_IV_LEN], ct: &[u8]) -> Result<Vec<u8>> {
    let cipher = Aes256Gcm::new(key.into());
    cipher
        .decrypt(&Nonce::from(*iv), ct)
        .map_err(|e| anyhow!("aes-gcm decrypt: {e}"))
}

pub fn pbkdf2_derive(passphrase: &str, salt: &[u8]) -> [u8; PBKDF2_OUT_LEN] {
    let mut out = [0u8; PBKDF2_OUT_LEN];
    pbkdf2_hmac::<Sha256>(passphrase.as_bytes(), salt, PBKDF2_ITERATIONS, &mut out);
    out
}

pub fn b64u_encode(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

#[allow(dead_code)]
pub fn b64u_decode(s: &str) -> Result<Vec<u8>> {
    URL_SAFE_NO_PAD
        .decode(s)
        .map_err(|e| anyhow!("base64url decode: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aes_gcm_roundtrip() {
        let key = [0u8; 32];
        let iv = [0u8; 12];
        let pt = b"hello";
        let ct = aes_encrypt(&key, &iv, pt).unwrap();
        let back = aes_decrypt(&key, &iv, &ct).unwrap();
        assert_eq!(back, pt);
    }

    #[test]
    fn aes_gcm_appends_16_byte_tag() {
        let key = [0u8; 32];
        let iv = [0u8; 12];
        let pt = b"x";
        let ct = aes_encrypt(&key, &iv, pt).unwrap();
        assert_eq!(ct.len(), pt.len() + 16);
    }

    #[test]
    fn pbkdf2_returns_32_bytes() {
        // The cross-implementation value match against WebCrypto lives in
        // tests/golden.rs (vectors in tests/fixtures/vectors.json). Here we
        // only assert the shape.
        let salt = vec![1u8; 16];
        let out = pbkdf2_derive("any passphrase", &salt);
        assert_eq!(out.len(), 32);
    }

    #[test]
    fn b64url_no_padding() {
        assert_eq!(b64u_encode(&[0xfb, 0xff]), "-_8");
        assert_eq!(b64u_decode("-_8").unwrap(), vec![0xfb, 0xff]);
    }
}
