#!/bin/bash
# Package the built linkrypt CLI binary into a tar.gz with sha256 sidecar.
# Usage:
#   scripts/package-cli.sh <target-triple>
# Example:
#   scripts/package-cli.sh aarch64-apple-darwin
#
# Inputs (relative to cwd):
#   cli/target/<target>/release/linkrypt       — built binary (required)
#   LICENSE                                     — root LICENSE (optional)
#   cli/README.md                               — CLI README (optional)
#
# Outputs (cwd):
#   linkrypt-<target>.tar.gz                    — staged tarball
#   linkrypt-<target>.tar.gz.sha256             — `<hex>  <filename>` sidecar

set -euo pipefail

TARGET="${1:?Usage: $0 <target-triple>}"
BIN_NAME="linkrypt"

BIN_PATH="cli/target/${TARGET}/release/${BIN_NAME}"
[ -x "$BIN_PATH" ] || { echo "package-cli: binary not found or not executable: $BIN_PATH" >&2; exit 1; }

DIST=$(mktemp -d)
trap 'rm -rf "$DIST"' EXIT

cp "$BIN_PATH" "$DIST/${BIN_NAME}"
[ -f LICENSE ]       && cp LICENSE       "$DIST/"
[ -f cli/README.md ] && cp cli/README.md "$DIST/"

ARCHIVE="${BIN_NAME}-${TARGET}.tar.gz"
SHA="${ARCHIVE}.sha256"

# Pack contents (not the directory itself) so extraction lands files at top level.
tar -czf "$ARCHIVE" -C "$DIST" .

# OS-conditional sha256 — sha256sum on Linux (BusyBox-included), shasum on macOS.
# Output format matches shasum: `<hex>  <filename>`.
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$ARCHIVE" > "$SHA"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARCHIVE" > "$SHA"
else
  echo "package-cli: neither sha256sum nor shasum found" >&2
  exit 1
fi

echo "$ARCHIVE"
echo "$SHA"
