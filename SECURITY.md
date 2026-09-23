# Security policy

Linkrypt's clients encrypt share contents before they leave your device, so a
flaw in them matters. See the README for what the service can see. Please report vulnerabilities privately.

## Reporting

Use GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/IZZY-Agency/linkrypt/security/advisories/new).
Do not open a public issue for a security problem.

Include the component (CLI or macOS app), the version (`linkrypt --version`,
or Linkrypt → About), what you found, and how to reproduce it. We acknowledge
reports within a few working days.

## Scope

In scope: the code in this repository — the `linkrypt` CLI and the Linkrypt
macOS app, including their encryption, key handling and local storage.

The linkrypt.sh service itself is not in this repository. Report issues with
it through the same private channel.

## Supported versions

Only the latest release of each component receives fixes.
