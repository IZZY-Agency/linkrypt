//! http.rs — integration tests for the ureq-3 HTTP layer (cli/src/api.rs).
//!
//! These pin the client's external contract against a real local HTTP
//! server:
//!   - success JSON decoding
//!   - the error MESSAGE contract ("unauthorized — " / "forbidden — " /
//!     "{code}: {msg}") that error.rs exit-code routing and
//!     login.rs::map_whoami_err depend on
//!   - empty-body 204 handling (revoke)
//!   - put_r2 rejecting a non-2xx presigned PUT (under ureq 3's
//!     http_status_as_error(false), Ok(response) no longer implies 2xx —
//!     the old v2-shaped code would have treated 403 here as success)
//!   - network-error mapping ("network: ...")

use linkrypt_cli::api::Client;

fn client(base: &str) -> Client {
    Client::new(base.to_string(), "lk_test_token".to_string(), false)
}

#[test]
fn whoami_decodes_success_json() {
    let mut server = mockito::Server::new();
    let m = server
        .mock("GET", "/api/cli/whoami")
        .match_header("authorization", "Bearer lk_test_token")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"userId":"user_1","scopes":["shares:read"]}"#)
        .create();
    let v = client(&server.url())
        .whoami()
        .expect("whoami should succeed");
    assert_eq!(v["userId"], "user_1");
    m.assert();
}

#[test]
fn error_401_maps_to_unauthorized_prefix() {
    let mut server = mockito::Server::new();
    server
        .mock("GET", "/api/cli/whoami")
        .with_status(401)
        .with_body(r#"{"error":"unauthorized"}"#)
        .create();
    let err = client(&server.url()).whoami().unwrap_err().to_string();
    // Load-bearing prefix: error.rs routes it to CliError::Unauthorized.
    assert!(err.starts_with("unauthorized — "), "got: {err}");
}

#[test]
fn error_403_maps_to_forbidden_prefix_with_body() {
    let mut server = mockito::Server::new();
    server
        .mock("GET", "/api/cli/whoami")
        .with_status(403)
        .with_body("scope missing")
        .create();
    let err = client(&server.url()).whoami().unwrap_err().to_string();
    assert!(err.starts_with("forbidden — "), "got: {err}");
    assert!(err.contains("scope missing"), "got: {err}");
}

#[test]
fn error_500_maps_to_code_and_body_not_unauthorized() {
    let mut server = mockito::Server::new();
    server
        .mock("GET", "/api/cli/whoami")
        .with_status(500)
        .with_body("internal")
        .create();
    let err = client(&server.url()).whoami().unwrap_err().to_string();
    assert!(err.starts_with("500: "), "got: {err}");
    // login.rs::map_whoami_err must NOT read this as a rejected token.
    assert!(!err.starts_with("unauthorized"), "got: {err}");
}

#[test]
fn revoke_accepts_204_empty_body() {
    let mut server = mockito::Server::new();
    let m = server
        .mock("DELETE", "/api/cli/revoke/abc123")
        .with_status(204)
        .create();
    client(&server.url())
        .revoke_share("abc123")
        .expect("204 with empty body must be success");
    m.assert();
}

#[test]
fn put_r2_rejects_non_2xx() {
    // The presigned-PUT path has no JSON contract; under ureq 3's
    // non-erroring model a 403 comes back as Ok(response) — the client
    // must still fail it, not report a successful upload.
    let mut server = mockito::Server::new();
    server
        .mock("PUT", "/bucket/key")
        .with_status(403)
        .with_body("SignatureDoesNotMatch")
        .create();
    let url = format!("{}/bucket/key", server.url());
    let err = client(&server.url())
        .put_r2(&url, b"ciphertext")
        .unwrap_err()
        .to_string();
    assert!(err.starts_with("forbidden — "), "got: {err}");
    assert!(err.contains("r2 PUT"), "got: {err}");
}

#[test]
fn put_r2_accepts_2xx() {
    let mut server = mockito::Server::new();
    let m = server.mock("PUT", "/bucket/key").with_status(200).create();
    let url = format!("{}/bucket/key", server.url());
    client(&server.url())
        .put_r2(&url, b"ciphertext")
        .expect("2xx PUT must succeed");
    m.assert();
}

#[test]
fn network_error_maps_to_network_prefix() {
    // Nothing listens on this port (bound-then-dropped to find a free one).
    let port = {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        l.local_addr().unwrap().port()
    };
    let err = client(&format!("http://127.0.0.1:{port}"))
        .whoami()
        .unwrap_err()
        .to_string();
    assert!(err.starts_with("network: "), "got: {err}");
}
