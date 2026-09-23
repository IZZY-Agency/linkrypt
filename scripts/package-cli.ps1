# Package the built linkrypt CLI exe into a zip with sha256 sidecar.
# Usage:
#   scripts/package-cli.ps1 -Target <target-triple>
# Example:
#   scripts/package-cli.ps1 -Target x86_64-pc-windows-msvc
#
# Inputs (relative to cwd):
#   cli\target\<target>\release\linkrypt.exe - built binary (required)
#   LICENSE                                  - root LICENSE (optional)
#   cli\README.md                            - CLI README (optional)
#
# Outputs (cwd):
#   linkrypt-<target>.zip                    - staged zip
#   linkrypt-<target>.zip.sha256             - `<hex>  <filename>` sidecar

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Target
)
$ErrorActionPreference = 'Stop'

$binName = 'linkrypt'
$binPath = Join-Path "cli\target\$Target\release" "$binName.exe"
if (-not (Test-Path $binPath)) {
  Write-Error "package-cli: binary not found: $binPath"
  exit 1
}

$dist = Join-Path $env:TEMP ("package-cli-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dist | Out-Null
try {
  Copy-Item -Path $binPath -Destination (Join-Path $dist "$binName.exe")
  if (Test-Path 'LICENSE')       { Copy-Item -Path 'LICENSE'       -Destination $dist }
  if (Test-Path 'cli\README.md') { Copy-Item -Path 'cli\README.md' -Destination $dist }

  $archive = "$binName-$Target.zip"
  $sha     = "$archive.sha256"

  # Use Compress-Archive (built into PowerShell 5.1+) so we don't depend on
  # 7z or other third-party packagers. -Force overwrites if a prior run left
  # the file behind (idempotent local re-runs).
  Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $archive -Force

  # Match shasum's `<hex>  <filename>` format (two-space separator).
  $hex = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
  Set-Content -Path $sha -Value "$hex  $archive" -NoNewline -Encoding ASCII

  Write-Output $archive
  Write-Output $sha
} finally {
  Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
}
