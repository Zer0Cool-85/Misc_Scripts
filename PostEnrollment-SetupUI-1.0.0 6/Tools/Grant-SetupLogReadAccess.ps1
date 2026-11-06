#Requires -Version 5.1
#Requires -RunAsAdministrator
<# Grants read-only access to existing run folders. No application steps run.
   Parent directory grants apply to the directory itself, not completion state. #>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Config/Setup.json'),
    [string]$ReaderSid = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
    [string]$RunName = '',
    [switch]$AllRuns
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$packageRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $packageRoot 'Core/Setup.Common.ps1')
if ($ReaderSid -in @('S-1-5-18','S-1-5-19','S-1-5-20','S-1-5-32-544')) {
    throw 'Supply -ReaderSid with the Windows user SID that needs File Explorer access. SYSTEM/Administrators already have access.'
}
$ReaderSid = ([Security.Principal.SecurityIdentifier]::new($ReaderSid)).Value
if ($AllRuns -and $RunName) { throw 'Choose -AllRuns or -RunName, not both.' }
$cfg = Read-SetupConfiguration -Path $ConfigPath -PackageRoot $packageRoot
$base = [Environment]::ExpandEnvironmentVariables([string]$cfg.Behavior.StateDirectory)
if (-not [IO.Path]::IsPathRooted($base) -or $base.StartsWith('\\')) { throw 'StateDirectory must be an absolute local path.' }
$stateRoot = Join-Path $base $cfg.SetupId
$runsRoot = Join-Path $stateRoot 'Runs'
foreach ($path in @($stateRoot,$runsRoot)) {
    $folder = Get-Item -LiteralPath $path -Force
    if (-not $folder.PSIsContainer -or ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Not a real directory: $path" }
}
$runs = @(Get-ChildItem -LiteralPath $runsRoot -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}-[0-9a-f]{8}$' } | Sort-Object Name -Descending)
if ($RunName) { $runs = @($runs | Where-Object Name -eq $RunName) }
elseif (-not $AllRuns) { $runs = @($runs | Select-Object -First 1) }
if (-not $runs.Count) { throw 'No matching live run folders were found for this configuration.' }
foreach ($run in $runs) {
    if ($run.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing a run folder that is a link: $($run.FullName)" }
}
Add-SetupLogReaderAccess -Path $stateRoot -ReaderSid $ReaderSid
Add-SetupLogReaderAccess -Path $runsRoot -ReaderSid $ReaderSid
foreach ($run in $runs) {
    Add-SetupLogReaderAccess -Path $run.FullName -ReaderSid $ReaderSid -InheritReaderAccess
    Write-Host "Granted read-only access for $ReaderSid to $($run.FullName)"
}
Write-Host 'Completion-state permissions are unchanged. Existing files inherit the run-folder read grant unless they have separately protected ACLs.'
