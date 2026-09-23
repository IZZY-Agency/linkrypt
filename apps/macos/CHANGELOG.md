# Changelog

All notable changes to Linkrypt for macOS. Versions match `MARKETING_VERSION` in `Linkrypt/project.yml`.

## 1.0.0

- First public release: source at [github.com/IZZY-Agency/linkrypt](https://github.com/IZZY-Agency/linkrypt).
- Developer ID-signed and notarized DMG, published on [GitHub Releases](https://github.com/IZZY-Agency/linkrypt/releases/latest).
- Homebrew cask: `brew install --cask izzy-agency/tap/linkrypt`.
- The JetBrains Mono license text (SIL OFL 1.1) now ships with the source.
- New README with install instructions, a feature overview and build-from-source steps. The docs now state that the ⌥⇧V hotkey needs no Accessibility or Input Monitoring permission.

## 0.1.2

- Every build is signed with a Developer ID and uses the hardened runtime. Because the signing identity no longer changes between builds, a Keychain "Always Allow" grant stays in place after updates.
- Release DMGs are notarized by Apple and stapled, so Gatekeeper opens them without warnings.

## 0.1.1

- Rebuilt with Xcode 27 for macOS 27. No functional changes.

## 0.1.0

First release of the native macOS app for [linkrypt.sh](https://linkrypt.sh).

- **Menu bar app**: paste-to-share, one-click *Encrypt clipboard now*, recent shares, and quick access to the dashboard, Settings and About.
- **⌥⇧V quick share**: a system-wide hotkey opens a floating panel with a preview of the clipboard. Pick an expiry and an open count (`e` / `o`), press ⏎, and the encrypted link is copied. The panel closes itself after a short countdown.
- **Composer** (⌘N): encrypt text or a file (you can also drop a file on the Dock icon or load a `.env` file into the text box). Set a label, expiry and maximum number of opens. Options: passphrase 2FA (Argon2id), email the link to a recipient, and a notification when the share is opened. After you create a share, the app shows the link and a QR code.
- **End-to-end encryption on the device**: AES-256-GCM with a random per-share key, length-hiding padding for all share types, and Argon2id passphrase derivation. It is byte-compatible with the web app and the CLI.
- **Dashboard**: shares and request links with status, copy and revoke. Keyboard driven (`j`/`k`, ⏎, `y`, `d d`, numbered tabs, and `g` chords for every sidebar item). The options offered match what your plan allows.
- **Open a share**: paste a Linkrypt link and the app decrypts it locally. Text is revealed in the window, and files are saved to disk. Passphrase-protected shares are supported.
- **Request links**: create and track keyless request links, answer someone else's request with encrypted text or a file, and read submitted answers in the request inbox (decrypted locally and burned after reading).
- **App lock**: optional Touch ID lock with an auto-lock grace period. With the lock on, the app locks right away on screen sleep or user switch. Open windows and drafts survive locking.
- **Clipboard hygiene**: copied links can be cleared from the clipboard automatically. Copy links for your own shares are kept in the Keychain, never in plain preferences.
- **Settings**: General (start at login, launch hidden, show in Dock, global hotkey, language), Sharing (quick-share defaults, clipboard burn, link persistence) and Security (Touch ID, auto-lock).
- **About window** with version, build and acknowledgements.
- **Languages**: English, French and Ukrainian, with a language switch inside the app.
