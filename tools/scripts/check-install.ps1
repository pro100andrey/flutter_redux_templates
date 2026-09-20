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
