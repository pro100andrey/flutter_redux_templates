<#
.SYNOPSIS
  frx installer — Windows.

.DESCRIPTION
  Downloads the release archive for this machine from GitHub, verifies it against
  the release's checksums.txt, and puts frx.exe in %LOCALAPPDATA%\frx\bin.

    irm https://raw.githubusercontent.com/pro100andrey/flutter_redux_templates/main/tools/scripts/install.ps1 | iex

  To pass options, download first — `iex` cannot forward arguments:

    irm https://raw.githubusercontent.com/pro100andrey/flutter_redux_templates/main/tools/scripts/install.ps1 -OutFile install.ps1
    .\install.ps1 -Version 0.2.0

.PARAMETER Version
  A specific release instead of the latest. With or without the leading `v`.

.PARAMETER Dir
  Install location. Defaults to %LOCALAPPDATA%\frx\bin.

.PARAMETER NoModifyPath
  Leave the user PATH alone. The VSCode extension finds the binary either way;
  this only affects typing `frx` in a terminal.

.NOTES
  Environment: FRX_VERSION, FRX_INSTALL_DIR, and FRX_DOWNLOAD_BASE to fetch the
  release assets from an internal mirror instead of github.com.
#>
[CmdletBinding()]
param(
  [string] $Version = $env:FRX_VERSION,
  [string] $Dir     = $env:FRX_INSTALL_DIR,
  [switch] $NoModifyPath
)

$ErrorActionPreference = 'Stop'
# TLS 1.2 is the floor GitHub accepts, and Windows PowerShell 5.1 — still the
# default shell on a fresh machine — negotiates SSL3/TLS1.0 unless told
# otherwise. Without this the download fails with a connection reset that reads
# like a network problem.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'pro100andrey/flutter_redux_templates'
if (-not $Dir) { $Dir = Join-Path $env:LOCALAPPDATA 'frx\bin' }

function Fail([string] $Message) { Write-Error "frx: $Message"; exit 1 }

<#
.SYNOPSIS
  The `Location` header off a redirect response, whichever PowerShell this is.

.DESCRIPTION
  The two editions hand back different objects and neither reads the other's way.
  Windows PowerShell 5.1 — still the default shell on a fresh machine, and the
  edition the TLS 1.2 line above exists for — gives an `HttpWebResponse` whose
  `Headers` is a `WebHeaderCollection`: indexed by name, no `Location` property.
  PowerShell 7 gives an `HttpResponseMessage` whose `Headers` is an
  `HttpResponseHeaders`: a `Location` property of type `Uri`, and no string
  indexer. Reading it one way meant the documented `irm | iex` one-liner reported
  "could not reach github.com" on the very edition it is aimed at.

  Both reads are attempted and both are allowed to fail, because "this shape does
  not have that member" is the normal answer for one of them.
#>
function Get-RedirectLocation($Response) {
  if (-not $Response) { return $null }
  $headers = $Response.Headers
  if (-not $headers) { return $null }

  $value = $null
  try { $value = $headers.Location } catch { <# not the property-bearing shape #> }
  if (-not $value) {
    try { $value = $headers['Location'] } catch { <# nor the indexable one #> }
  }
  # A header collection may hand back a single string or a collection of them.
  if ($value -is [array]) { $value = $value | Select-Object -First 1 }
  if (-not $value) { return $null }
  return [string] $value
}

# --- platform ---------------------------------------------------------------

# Only x64 is built. Windows on ARM runs x64 binaries under emulation, so an
# ARM machine gets a working frx rather than a refusal — slower to start, and
# nothing else about it differs.
$arch = 'x64'

# --- which release ----------------------------------------------------------

if (-not $Version) {
  # The redirect /releases/latest performs, not the JSON API: unauthenticated
  # api.github.com is rate-limited to 60 requests an hour per IP, and behind a
  # corporate NAT that budget is shared with everyone else.
  $response = $null
  try {
    $response = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" `
      -MaximumRedirection 0 -ErrorAction Stop -UseBasicParsing
  } catch {
    # Both editions treat a 302 under `-MaximumRedirection 0` as an error; the
    # response — and the Location with it — rides on the exception.
    $response = $_.Exception.Response
  }
  $location = Get-RedirectLocation $response
  if (-not $location) { Fail "could not reach github.com to resolve the latest release — pass -Version <x.y.z>" }

  # Matched, not stripped. `-replace '.*/tag/v?'` returns the subject unchanged
  # when the pattern does not match, so a redirect that lands anywhere but a tag
  # — which is what a repository whose only releases are prereleases does — left
  # the entire URL sitting in $Version and produced a download URL built out of it.
  # Phrased as a positive match so `$Matches` is unambiguously populated —
  # whether `-notmatch` fills it is a detail not worth depending on.
  if ($location -match '/tag/v?(?<tag>[^/]+?)/?$') {
    $Version = $Matches['tag']
  } else {
    Fail "github.com redirected to '$location', which names no release tag. That is what a repository with no published (non-prerelease) release looks like — pass -Version <x.y.z>."
  }
}
$Version = $Version -replace '^v', ''

$asset = "frx-$Version-windows-$arch.zip"
# Overridable for an internal mirror of the release assets, exactly as
# `install.sh` is — `tools/README.md` documents the variable for both scripts,
# and one of them silently ignoring it is worse than not offering it at all: the
# install appears to work and pulls from the internet the mirror exists to avoid.
$base = if ($env:FRX_DOWNLOAD_BASE) {
  $env:FRX_DOWNLOAD_BASE
} else {
  "https://github.com/$Repo/releases/download/v$Version"
}

# --- download & verify ------------------------------------------------------

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("frx-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  Write-Host "frx $Version · windows-$arch"
  Write-Host "  v $asset"

  # The underlying error is carried through, not replaced by a guess at what it
  # meant. Every failure here used to be reported as "no asset in release" — so a
  # proxy refusal, a TLS failure or a full disk all sent the user to a release
  # page where the asset is plainly present, to conclude the message was wrong
  # and stop reading it.
  try {
    Invoke-WebRequest -Uri "$base/$asset" -OutFile (Join-Path $tmp $asset) -UseBasicParsing
  } catch {
    Fail ("could not download '$asset' from release v$Version — " +
      "$($_.Exception.Message) If the release exists, check " +
      "https://github.com/$Repo/releases/tag/v$Version for the asset.")
  }
  try {
    Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile (Join-Path $tmp 'checksums.txt') -UseBasicParsing
  } catch {
    Fail ("could not download checksums.txt for release v$Version — " +
      "$($_.Exception.Message) Refusing to install an unverified binary.")
  }

  # checksums.txt is `<sha256>  <filename>` per line, covering every platform's
  # archive plus the VSIX. Match the one line naming this asset; its absence is
  # itself a reason to stop.
  $line = Get-Content (Join-Path $tmp 'checksums.txt') |
    Where-Object { $_ -match "\s\*?$([regex]::Escape($asset))$" } |
    Select-Object -First 1
  if (-not $line) { Fail "$asset is not listed in checksums.txt" }

  $expected = ($line -split '\s+')[0]
  $actual = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $tmp $asset)).Hash
  if ($actual -ne $expected.ToUpperInvariant()) {
    Fail "checksum mismatch for $asset — the download is corrupt or tampered with"
  }
  Write-Host '  + checksum'

  # --- install --------------------------------------------------------------

  Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath $tmp -Force
  $exe = Join-Path $tmp 'frx.exe'
  if (-not (Test-Path $exe)) { Fail "the archive did not contain 'frx.exe'" }

  New-Item -ItemType Directory -Path $Dir -Force | Out-Null
  $target = Join-Path $Dir 'frx.exe'
  # Windows locks a running executable, so an upgrade while an editor holds the
  # old one cannot overwrite in place. Renaming the locked file out of the way
  # succeeds where a delete would not; the leftover is swept on the next run.
  if (Test-Path $target) {
    $stale = "$target.old"
    Remove-Item $stale -Force -ErrorAction SilentlyContinue
    try { Move-Item $target $stale -Force } catch {
      # Held by something that will not let go. Move-Item on the new binary
      # below fails next and reports it; there is nothing to add here.
    }
  }
  Move-Item $exe $target -Force
  Write-Host "  > $target"

  # --- PATH -----------------------------------------------------------------

  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $onPath = ($userPath -split ';' | Where-Object { $_.TrimEnd('\') -ieq $Dir.TrimEnd('\') }).Count -gt 0

  if ($onPath) {
    Write-Host ''
    Write-Host "frx $Version installed — run 'frx --help'"
  } elseif ($NoModifyPath) {
    Write-Host ''
    Write-Host "frx $Version installed, but $Dir is not on your PATH. Add it:"
    Write-Host "    setx PATH `"$Dir;%PATH%`""
  } else {
    # The *user* PATH, never the machine one: this install is per-user and does
    # not run elevated. Read-modify-write of the User value only — expanding and
    # rewriting the whole of $env:Path would bake the machine entries into the
    # user's, which survives uninstalling whatever put them there.
    $updated = if ([string]::IsNullOrEmpty($userPath)) { $Dir } else { "$userPath;$Dir" }
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    $env:Path = "$env:Path;$Dir"
    Write-Host "  > PATH updated for the current user"
    Write-Host ''
    Write-Host "frx $Version installed — open a new terminal to pick it up."
  }

  Write-Host ''
  Write-Host 'The VSCode extension (search "FRX" in the Marketplace) finds this binary'
  Write-Host 'even when the editor was launched from the Start menu with a different PATH.'
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
