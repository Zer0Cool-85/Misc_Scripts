#requires -Version 5.1
[CmdletBinding()]
param([string]$Path=(Join-Path $PSScriptRoot 'Source\PolicyConfig.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Source\PolicyEngine.psm1') -Force -DisableNameChecking
$config=Read-PolicyConfiguration $Path
Write-Output "Valid: $($config.ConfigurationId)"
$config.Desired | Select-Object Name,Present,Kind,Value | Format-Table -AutoSize -Wrap
