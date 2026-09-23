# Parses and analyses install.ps1 — the `installer-ps1` task, run by CI's
# `installers` job through `xtask ci-installers`.
#
# A parse error in install.ps1 cannot be caught by running it — the failure
# mode is `irm | iex` aborting on a machine with no PowerShell developer
# tooling. PSScriptAnalyzer additionally catches the ones that parse: an
# unapproved verb, a cmdlet that does not exist.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'install.ps1'

$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  $script, [ref]$null, [ref]$errors) | Out-Null
if ($errors) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }

Install-Module PSScriptAnalyzer -Force -Scope CurrentUser -ErrorAction Stop
$found = Invoke-ScriptAnalyzer -Path $script
# Warnings are printed, not gated. Several of them are style rules an installer
# is right to break — `Write-Host` is exactly how a script that talks to a
# person should talk to them, and PSScriptAnalyzer objects to it in every
# script alike. Errors are the ones that mean the script does not do what it
# says.
if ($found) { $found | Format-Table -AutoSize | Out-String | Write-Host }
if ($found | Where-Object Severity -eq 'Error') { exit 1 }
Write-Host "install.ps1 parses and analyses clean"

# Run the way the README runs it — `irm … | iex` — and check what it leaves in
# the calling session. iex evaluates in the caller's scope, so a top-level
# `$ErrorActionPreference = 'Stop'` used to outlive the install and change how
# the user's next command failed, along with every variable and function the
# script defined. The mirror is unreachable on purpose: the script gets far
# enough to set everything up, then fails on the first download, which also
# checks that a failure throws rather than `exit`ing the user's session.
$env:FRX_VERSION = '0.0.0'
$env:FRX_DOWNLOAD_BASE = 'http://127.0.0.1:1/unreachable'
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [IO.Path]::GetTempPath() }
$ErrorActionPreference = 'Continue'
$threw = $null
try { Get-Content $script -Raw | Invoke-Expression } catch { $threw = "$_" }
$problems = @()
if ($threw -notlike 'frx: *') { $problems += "a failed download should throw 'frx: …', got: $threw" }
if ($ErrorActionPreference -ne 'Continue') { $problems += "`$ErrorActionPreference leaked as $ErrorActionPreference" }
foreach ($name in 'Repo', 'tmp', 'asset', 'base') {
  if (Get-Variable $name -ErrorAction SilentlyContinue) { $problems += "`$$name leaked into the session" }
}
if (Get-Command Fail -ErrorAction SilentlyContinue) { $problems += 'function Fail leaked into the session' }
if ($problems) { $problems | ForEach-Object { Write-Host "FAIL: $_" }; exit 1 }
Write-Host "install.ps1 under iex leaves the session as it found it"
