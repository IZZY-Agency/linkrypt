# Linkrypt for macOS

Native macOS app (SwiftUI) for zero-knowledge encrypted sharing with [linkrypt.sh](https://linkrypt.sh). Secrets and files are encrypted on your Mac before anything is uploaded. The key travels only in the link's `#fragment`, which browsers never send to the server.

## Install

With Homebrew:

```bash
brew install --cask izzy-agency/tap/linkrypt
```

Or download the latest DMG from [GitHub Releases](https://github.com/IZZY-Agency/linkrypt/releases/latest), open it and drag **Linkrypt** to **Applications**. The DMG is signed with a Developer ID and notarized by Apple.

On first launch, paste an API token from your linkrypt.sh account (**API tokens** page, `/app/tokens`).

### Requirements

- macOS 15.0 or later
- A linkrypt.sh account and an API token

## Features

- **Menu bar item**: paste-to-share, *Encrypt clipboard now* using your default expiry and open count, a list of recent shares, and shortcuts to the dashboard, Settings and About.
- **⌥⇧V quick share**: a system-wide hotkey opens a floating panel with a preview of the clipboard. Pick an expiry and an open count (`e` / `o` cycle them), press ⏎, and the encrypted link replaces the clipboard contents.
- **Composer** (⌘N): share text or a file (you can also drop a file on the Dock icon). Set a label, expiry and maximum number of opens, and optionally add passphrase 2FA (Argon2id), email the link to a recipient, or get notified when it is opened. After you create a share, the app shows the link and a QR code.
- **Dashboard**: your shares and request links with status, copy and revoke. Keyboard driven: `j`/`k` move, ⏎ opens, `y` copies, `d d` revokes, and `g` chords (`g s`, `g r`, `g n`, …) switch views.
- **Open a share**: paste a Linkrypt link and the app decrypts it locally. Text is revealed in the window, and files are saved to disk. Passphrase-protected shares are supported.
- **Request links**: create a keyless request link and track its status. **Answer a request** by encrypting text or a file for someone else's request link. Read submitted answers in the **Request inbox**: they are decrypted locally and burned after reading.
- **App lock**: optional Touch ID lock with a configurable auto-lock grace period. With the lock on, the app also locks right away on screen sleep or when you switch users, and unlocking then always needs Touch ID.
- **Clipboard hygiene**: copied links can be cleared from the clipboard automatically ("burn copied links").
- **Languages**: English, French and Ukrainian. You can switch the language in the app, and it applies immediately.

### Settings

**Settings** (⌘, · app menu · ⚙ in the menu-bar popover · dashboard sidebar) has three tabs:

- **General**: *Start at login* (`SMAppService`; macOS may hold it in **System Settings › General › Login Items** until you approve it, and the toggle then shows a hint and a link), *Launch hidden* (only the menu-bar item at startup), *Show in Dock*, *Global hotkey ⌥⇧V* on/off, language.
- **Sharing**: quick-share defaults (expiry / opens) for ⌥⇧V and *Encrypt clipboard now*, clipboard burn, and *Persist links across launches*. Copy links are stored in the Keychain and never in `UserDefaults`.
- **Security**: *Require Touch ID* and the auto-lock grace period.

> **Login item caveat:** the registration is bound to the app bundle's path. Run Linkrypt from a stable location (e.g. `/Applications`), not from Xcode's DerivedData, or the item breaks when the build folder changes.

### Global hotkey ⌥⇧V

The hotkey is registered with Carbon's `RegisterEventHotKey`. It needs **no** Accessibility or Input Monitoring permission. If another app already owns ⌥⇧V, Settings › General says so. You can turn the hotkey off there.

## Security model

All encryption happens on your Mac: AES-256-GCM with a random key per share, length-hiding padding, and Argon2id for passphrase 2FA. The server stores only ciphertext. The key lives only in the URL fragment, which is never sent to the server. **One exception:** when you use the optional *Email the link to a recipient*, the full recipient URL (including the key fragment) goes to the server so it can send the email.

The API token and the on-device copy links are stored in the macOS Keychain (`ThisDeviceOnly`). They do not sync to iCloud.

## Build from source

Requirements: Xcode 27 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd apps/macos/Linkrypt
xcodegen generate            # regenerate Linkrypt.xcodeproj from project.yml
xcodebuild -project Linkrypt.xcodeproj -scheme Linkrypt \
  -destination 'platform=macOS' -configuration Release build \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

`project.yml` signs every configuration with the maintainers' Developer ID. Without that certificate, add the `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` override shown above to get an ad-hoc signed build. You can also open `Linkrypt.xcodeproj` in Xcode and pick your own team under *Signing & Capabilities*.

Re-run `xcodegen generate` whenever you add files or edit `project.yml`.

### Tests

Crypto, link parsing, API clients, the app-lock state machine and the other logic live in the `LinkryptCore` Swift package. Its tests run without the app:

```bash
cd apps/macos/LinkryptCore
swift test
```

The crypto golden tests read the shared vectors in `cli/tests/fixtures/vectors.json`, so the macOS app and the CLI stay byte-compatible.

The translation check fails if any string in the catalog is missing a French or Ukrainian translation:

```bash
node apps/macos/scripts/check-localization.mjs
```

### Release (maintainers)

`apps/macos/scripts/release.sh` archives, exports with Developer ID, notarizes and staples the app, then builds, signs, notarizes and staples the DMG. It needs the Developer ID certificate and a `notarytool` keychain profile. See the header of the script for the details.

## Architecture

- **LinkryptCore** (`../LinkryptCore`): a pure SwiftPM library with no UI. It holds the crypto, API clients, link parsing, token/link storage and the lock logic, and is unit-tested.
- **Linkrypt**: the SwiftUI app shell (menu bar, windows, hotkey panel). It depends on `LinkryptCore` as a local package.

## Fonts

JetBrains Mono (Regular, Medium, Bold) is bundled under the [SIL Open Font License 1.1](https://openfontlicense.org). The license text is in [`Linkrypt/Resources/JetBrainsMono-OFL.txt`](Linkrypt/Resources/JetBrainsMono-OFL.txt). Source: <https://github.com/JetBrains/JetBrainsMono>.
