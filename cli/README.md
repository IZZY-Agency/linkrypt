# linkrypt CLI

Command-line client for [linkrypt.sh](https://linkrypt.sh), an end-to-end-encrypted
share service. Text, files and piped input are encrypted locally with AES-256-GCM
before anything leaves your machine; the decryption key travels only in the URL
fragment (`#k=…&iv=…`), which browsers never send to the server. The exception
is `--to` (see below). Labels, file names and recipient addresses are sent in
the clear.

## Install

**Homebrew**

    brew install izzy-agency/tap/linkrypt-cli

**Install script (macOS, Linux)**

    curl -fsSL https://linkrypt.sh/install.sh | sh

Installs `linkrypt` into `~/.local/bin` (override with `INSTALL_DIR=/path`) and adds
a short `lk` alias next to it. On Linux the static musl build is used by default.

**Windows (PowerShell)**

    iwr -useb https://linkrypt.sh/install.ps1 | iex

Installs into `%LOCALAPPDATA%\linkrypt\bin` (override with `$env:INSTALL_DIR`),
also with an `lk` alias.

**Manual download**

Prebuilt archives for macOS (Apple Silicon, Intel), Linux (x86_64 musl/gnu,
aarch64 musl) and Windows (x86_64, ARM64) are attached to each `cli-v*` release at
<https://github.com/IZZY-Agency/linkrypt/releases>. Every archive
(`linkrypt-<target>.tar.gz` or `.zip`) has a matching `.sha256` file:

    shasum -a 256 -c linkrypt-aarch64-apple-darwin.tar.gz.sha256
    tar -xzf linkrypt-aarch64-apple-darwin.tar.gz

## Quick start

    linkrypt login                                  # paste a token from https://linkrypt.sh/app/tokens
    linkrypt create "secret"                        # prints the recipient URL
    linkrypt create --file ./report.pdf --expires 1h --opens 1
    echo "db password" | linkrypt create --passphrase --plain
    linkrypt list
    linkrypt revoke <id>

## Commands

| Command | Description |
|---|---|
| `login [--url <url>]` | Paste and verify an API token, save it to the current profile (creates `default` on first run) |
| `logout` | Delete the current profile and switch to the first remaining one (alphabetically); the config file is deleted when none is left. Check `env list` afterwards: you may now be pointed at another server |
| `create [TEXT]` | Encrypt and upload a new share from `TEXT`, `--file`, or piped stdin (exactly one) |
| `list` | List your active shares |
| `revoke <id>` | Revoke a share |
| `audit [--limit <n>]` | Show recent audit events |
| `healthz` | Probe the server's health endpoint (no token needed) |
| `env list` | List profiles; the current one is marked with `*` (tokens are never printed) |
| `env use <name>` | Switch the current profile |
| `env add <name> --url <url>` | Add a profile (prompts for and verifies its token) and switch to it |
| `env remove <name>` | Remove a profile other than the current one |

### `create` options

| Flag | Default | Description |
|---|---|---|
| `--file <path>` | | Share a file instead of text |
| `--filename <name>` | file's name | Filename shown to the recipient |
| `--expires <1h\|24h\|7d\|30d>` | `7d` | Lifetime of the share |
| `--opens <1-100>` | `1` | Number of times the share can be opened |
| `--label <text>` | | Label shown by `list` |
| `--passphrase [<value>]` | | Require a passphrase to open; with no value you are prompted (preferred, keeps it out of shell history) |
| `--to <email>` | | Email the link to a recipient (see note below) |
| `--notify-on-open` | off | Notify you when the share is opened |
| `--plain` | | Print only the URL |
| `--json` | | Print `{"id","url","expiresAt"}` as JSON |

The CLI caps encrypted size at 256 KiB for text and 100 MiB for files. Your account
plan may set lower limits and determines whether `--passphrase`, `--to` and
`--notify-on-open` are available.

`--to` hands the complete URL, including the key fragment, to the server so it
can send the email. Use it only when you are comfortable with that trade-off;
otherwise share the printed URL yourself.

### Global options and environment

| Option | Environment | Description |
|---|---|---|
| `--url <url>` | `LINKRYPT_API_URL` | Server origin for this invocation (overrides the profile) |
| | `LINKRYPT_API_TOKEN` | API token for this invocation (overrides the config file) |
| `--no-color` | `NO_COLOR` | Disable colored output (`FORCE_COLOR` forces it on) |
| `-v`, `--verbose` | | Log each HTTP request to stderr |
| | `LINKRYPT_ALLOW_HTTP` | Allow plain `http://` for `localhost` / `127.0.0.1` / `::1` only (local development) |

Exit codes: `0` success, `1` error, `2` bad usage, `3` unauthorized, `4` forbidden.

## Configuration

Tokens and profiles are stored in `config.json` in the per-user config directory:

| OS | Path |
|---|---|
| macOS | `~/Library/Application Support/linkrypt/config.json` |
| Linux | `$XDG_CONFIG_HOME/linkrypt/config.json` (default `~/.config/linkrypt/config.json`) |
| Windows | `%APPDATA%\linkrypt\config\config.json` |

On macOS and Linux the file is written with mode `0600`, and the CLI refuses to read
it if group or other permission bits are set. The default server is
`https://linkrypt.sh`.

## Build from source

Requires Rust 1.89 or newer.

    git clone https://github.com/IZZY-Agency/linkrypt
    cd linkrypt/cli
    cargo build --release
    # → target/release/linkrypt

    cargo test

## License

MIT
