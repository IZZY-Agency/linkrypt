# Linkrypt

End-to-end-encrypted sharing for text and files: a command-line tool and a
native macOS app for [linkrypt.sh](https://linkrypt.sh).

You encrypt on your own device, send a link, and the recipient decrypts in
their browser, the CLI or the app. For an ordinary share the decryption key
travels only in the link's `#fragment`, which browsers never send to a server,
so the service stores ciphertext it cannot read. The exceptions are listed
below.

[Website](https://linkrypt.sh) ·
[Releases](https://github.com/IZZY-Agency/linkrypt/releases) ·
[Issues](https://github.com/IZZY-Agency/linkrypt/issues)

## What is here

| Path | What it is |
|---|---|
| [`cli/`](cli) | `linkrypt`, the command-line client (Rust). macOS, Linux and Windows. |
| [`apps/macos/`](apps/macos) | Linkrypt for macOS (SwiftUI): menu bar, quick share on ⌥⇧V, send and receive, request links, Touch ID lock. |
| [`apps/macos/LinkryptCore/`](apps/macos/LinkryptCore) | The app's Swift package: crypto, link format, API client. |

The linkrypt.sh service (web app and API) is a hosted product and is not part
of this repository. Both clients talk to it over its public API with a
personal token you create at linkrypt.sh.

## How the encryption works

- Each share gets a fresh random 256-bit key and 96-bit IV. Content is
  encrypted with **AES-256-GCM** on your device before upload.
- The recipient link is `https://linkrypt.sh/<lang>/s/<id>#k=<key>&iv=<iv>`.
  The part after `#` stays in the browser; the server sees only `<id>`.
- The macOS app pads plaintext to a size bucket before encryption, so the
  stored ciphertext reveals only a size range, not the exact length. The CLI
  does not pad yet.
- An optional **passphrase** is a second factor, not part of the key: the
  client sends a salted hash of it (Argon2id, 64 MiB and 3 passes, in the
  macOS app; PBKDF2-SHA256 with 600,000 iterations in the CLI), and the server
  releases the ciphertext only to someone who knows it. Anyone holding the
  link still needs the passphrase to open the share.
- Shares can expire after a set time or a number of opens, and can be revoked.

**Where the service does see the key.** Two features hand the key to the
server so it can deliver something for you; content sent through them is
not zero-knowledge toward the service:

- **Email the link** (`--to` in the CLI, the email option in the app) sends the full
  link, key included, to the server, which mails it to the address you enter.
  Copy the link and send it yourself when that matters.
- **Request links.** When someone replies to your request link, their client
  encrypts the reply and sends the ciphertext together with its key to the
  server, which delivers it to your inbox.

**Metadata is not encrypted.** Labels, file names, recipient addresses, sizes
and expiry settings are sent in the clear so the service can show and enforce
them.

Both clients are tested byte-for-byte against the web implementation with the
shared vectors in [`cli/tests/fixtures/vectors.json`](cli/tests/fixtures/vectors.json).

## Install

### macOS app

Requires macOS 15 or newer. Signed with a Developer ID and notarized.

```sh
brew install --cask izzy-agency/tap/linkrypt
```

Or download the `.dmg` from the
[latest release](https://github.com/IZZY-Agency/linkrypt/releases/latest)
and drag Linkrypt to Applications.

### CLI

```sh
brew install izzy-agency/tap/linkrypt-cli        # macOS and Linux
curl -fsSL https://linkrypt.sh/install.sh | sh    # macOS and Linux
iwr -useb https://linkrypt.sh/install.ps1 | iex   # Windows (PowerShell)
```

Prebuilt archives for every platform, each with a `.sha256`, are attached to
the `cli-v*` [releases](https://github.com/IZZY-Agency/linkrypt/releases).
The macOS binaries are signed and notarized.

Then run `linkrypt login` and paste a token from linkrypt.sh. See
[`cli/README.md`](cli/README.md) for the commands.

## Build from source

CLI (Rust 1.89 or newer):

```sh
cd cli
cargo build --release     # → target/release/linkrypt
cargo test
```

macOS app (Xcode 26 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
cd apps/macos/LinkryptCore && swift test
cd ../Linkrypt && xcodegen generate
xcodebuild -project Linkrypt.xcodeproj -scheme Linkrypt -configuration Release \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

The empty `DEVELOPMENT_TEAM` and ad-hoc identity build without a signing
certificate. See [`apps/macos/Linkrypt/README.md`](apps/macos/Linkrypt/README.md).

## Releases

The two clients are versioned separately. CLI releases are tagged `cli-v*`,
app releases `macos-v*`; each has its own changelog:
[`cli/CHANGELOG.md`](cli/CHANGELOG.md),
[`apps/macos/CHANGELOG.md`](apps/macos/CHANGELOG.md).

## Security

Please report vulnerabilities privately. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The bundled JetBrains Mono font is under the SIL Open Font
License 1.1.
