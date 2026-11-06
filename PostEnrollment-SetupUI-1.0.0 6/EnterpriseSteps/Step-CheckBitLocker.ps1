[CmdletBinding()]
param([ValidateSet('Audit','RequireProtected')][string]$Mode='Audit', [bool]$AllowEncryptionInProgress=$false)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
. (Join-Path $PSScriptRoot 'Provisioning.Common.ps1')
$v=Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
if (-not $v) { throw "No BitLocker status returned for $env:SystemDrive." }
$verdict=Get-EncryptionVerdict ([string]$v.VolumeStatus) ([string]$v.ProtectionStatus) $AllowEncryptionInProgress
# Never serialize KeyProtector objects; they can contain recovery passwords.
$report=[ordered]@{ MountPoint=$env:SystemDrive; VolumeStatus=[string]$v.VolumeStatus; ProtectionStatus=[string]$v.ProtectionStatus; EncryptionMethod=[string]$v.EncryptionMethod; Percent=$v.EncryptionPercentage; Verdict=$verdict; Mode=$Mode; CheckedUtc=[DateTime]::UtcNow.ToString('o'); Escrow='Not checked' }
Write-SetupJson (Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID+'-BitLocker.json')) $report
$global:SetupUiStepSummary=("BitLocker: {0}; {1}, protection {2}, {3}% encrypted. Escrow not checked." -f $verdict,$v.VolumeStatus,$v.ProtectionStatus,$v.EncryptionPercentage)
Set-EnterpriseProgress $global:SetupUiStepSummary
if ($Mode -eq 'RequireProtected' -and $verdict -eq 'NeedsAttention') { throw 'OS volume does not meet the configured protection requirement. Review BitLocker policy and retry.' }
