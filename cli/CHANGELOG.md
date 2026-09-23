# Changelog

All notable changes to the linkrypt CLI. Releases are tagged `cli-v<version>`.

## 1.0.0

First public release. The source now lives at
[github.com/IZZY-Agency/linkrypt](https://github.com/IZZY-Agency/linkrypt).

### Added

- Named environment profiles: `linkrypt env list`, `env use <name>`,
  `env add <name> --url <url>` and `env remove <name>`. `login` updates the
  current profile (creating `default` on first run). `logout` deletes the current
  profile and switches to the first remaining one (alphabetically), or deletes the
  config file when none is left. Existing single-token config files are migrated
  automatically on first read.
- Config changes are serialized with a lock file, so concurrent invocations no
  longer lose each other's updates.
- Homebrew formula: `brew install izzy-agency/tap/linkrypt-cli`.
- macOS binaries are signed with a Developer ID and notarized by Apple.

### Changed

- A single `linkrypt` binary with `https://linkrypt.sh` as the default server.
- `healthz` without `--url` now probes the current profile's server instead of
  always using the default.
- Base URLs containing credentials (`https://user:pass@host`) are rejected.
- `login` reports "token rejected by server" only for an explicit 401. Server and
  network errors are shown as such, so a valid token is not reported as bad.
- Suspended accounts are refused by every CLI endpoint and surface as an
  unauthorized error (exit code 3).
- Dependency upgrades: ureq 3, the RustCrypto 0.11 line (aes-gcm 0.11, sha2 0.11,
  pbkdf2 0.13) and rand 0.10. All other dependencies refreshed to
  their current releases. Output remains byte-identical with the browser's
  WebCrypto implementation, verified against golden test vectors.
- Minimum supported Rust version is 1.89.

## 0.3.1

### Fixed

- Release builds for every platform are published again. 0.3.0 shipped assets for
  only one target.

## 0.3.0

### Changed

- The binary is named `linkrypt`, and the installers add a short `lk` alias.
  Release archives are named `linkrypt-<target>.tar.gz` / `.zip`.
- Renamed runtime identifiers to the linkrypt name: the environment variables are
  now `LINKRYPT_API_TOKEN`, `LINKRYPT_API_URL` and `LINKRYPT_ALLOW_HTTP`, API
  tokens use the `lk_` prefix, and the config directory is `linkrypt`.
- Dependency updates: directories 6, indicatif 0.18, thiserror 2.

## 0.2.2

### Fixed

- Windows builds: Unix-only file-permission code is now compiled only on Unix.
  On Windows the token file relies on the per-user profile directory's default
  access control instead of mode bits.

## 0.2.1

### Changed

- Updated rpassword to 7.5.3. This release was an attempt to fix the Windows
  build. The actual fix shipped in 0.2.2.

## 0.2.0

### Added

- Multi-platform releases: macOS (Apple Silicon, Intel), Linux (x86_64 musl and
  gnu, aarch64 musl) and Windows (x86_64, ARM64).
- Release archives ship with a `.sha256` checksum file.

## 0.1.1

### Changed

- Binaries are also published to the linkrypt download mirror used by the
  installer. No code changes.

## 0.1.0

Initial release (macOS on Apple Silicon only).

- `login`, `logout`, `healthz`, `list`, `revoke`, `audit` and `create`.
- `create` encrypts text, a file (`--file`) or piped stdin locally with
  AES-256-GCM. The key and IV are kept in the URL fragment and not sent to the
  server, unless you use `--to`, which asks the server to email the full link.
- Share options: `--expires`, `--opens`, `--label`, `--filename`, passphrase
  protection (`--passphrase`, PBKDF2-SHA256 with 600,000 iterations), email
  delivery (`--to`), `--notify-on-open`, and `--plain` / `--json` output.
- Progress bar for uploads larger than 1 MiB.
- The token is stored in a `0600` config file written atomically. HTTPS is
  required, except for `localhost` when plain HTTP is explicitly allowed through
  an environment variable.
- `curl | sh` installer.
