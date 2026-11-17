#requires -Version 5.1
<#
.SYNOPSIS
Renames an eligible DESKTOP-/LAPTOP- endpoint, records state, and requests restart.
.DESCRIPTION
Run as SYSTEM through Install.cmd. No restart is forced by this script.
AuditOnly prints its decision without changing the name, receipt or notification state.
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto','LT','DT','VM','SRV','PC')][string]$DeviceType = 'Auto',
    [switch]$NoRandomSuffix,
    [switch]$AuditOnly
)
$ErrorActionPreference = 'Stop'
$script:Component = 'Install'
try {
    . (Join-Path $PSScriptRoot 'Naming.Common.ps1')
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use Install.cmd to launch 64-bit Windows PowerShell.' }
    $state = Get-ComputerNameState
    Write-NamingLog "Active=$($state.ActiveName); configured=$($state.ConfiguredName); pending=$($state.PendingRename)."
    if ($state.PendingRename) {
        if ($AuditOnly) { Write-Output "Pending rename: $($state.ActiveName) -> $($state.ConfiguredName). No changes or popup in audit mode."; exit 0 }
        Show-PendingRenameReminder -NameState $state
        # Requirement normally prevents this branch. An existing receipt may be
        # detected, otherwise a later requirement evaluation blocks installation.
        Write-NamingLog 'Rename deferred because another rename is already pending.'
        exit 1618
    }
    # The generic-name gate takes precedence if a name happens to match both
    # patterns (for example DESKTOP-LT). Other custom names are never renamed.
    if (-not (Test-GenericWindowsComputerName -Name $state.ActiveName) -and
        (Test-NamingConvention -Name $state.ActiveName)) {
        if ($AuditOnly) { Write-Output "Already compliant: $($state.ActiveName)."; exit 0 }
        # Handles a change made by another actor after requirement evaluation.
        Save-RenameReceipt -TargetName $state.ActiveName
        Write-NamingLog 'Already compliant when installer ran; no rename performed.'
        exit 0
    }
    $eligible = Get-RenameEligibility -NameState $state
    if (-not $eligible.Eligible) {
        if ($AuditOnly) { Write-Output "Deferred: $($eligible.Reason)"; exit 0 }
        Write-NamingLog "Deferred: $($eligible.Reason)"
        exit 1618
    }
    $type = $DeviceType
    if ($type -eq 'Auto') { $type = Get-ComputerChassisType -ComputerSystem $eligible.System }
    $target = New-CompliantComputerName -Prefix $eligible.Prefix -DeviceType $type -NoRandomSuffix:$NoRandomSuffix
    if ($AuditOnly) { Write-Output "Would rename $($state.ActiveName) to $target (preview suffix can differ on the real run)."; exit 0 }
    # Reduce the requirement-to-install race window and avoid replacing a rename
    # staged by another management tool. Windows exposes no atomic check-and-rename.
    $latest = Get-ComputerNameState
    if ($latest.PendingRename -or $latest.ActiveName -ine $state.ActiveName) {
        Show-PendingRenameReminder -NameState $latest
        Write-NamingLog 'Name state changed before rename; retry later.'
        exit 1618
    }
    $latestAccount = (Get-CimInstance -ClassName Win32_ComputerSystem -Property UserName -ErrorAction Stop).UserName
    if ($latestAccount -ine $eligible.System.UserName) { Write-NamingLog 'Console user changed; retry later.'; exit 1618 }
    Write-NamingLog "Requesting rename to $target."
    $result = Rename-Computer -NewName $target -Force -PassThru -ErrorAction Stop
    if ($null -eq $result -or -not $result.HasSucceeded) { throw 'Rename-Computer did not confirm success.' }
    $after = Get-ComputerNameState
    if ($after.ConfiguredName -ine $target) { throw 'Rename was reported successful but the configured name did not match.' }
    # Notify even if writing the detection receipt subsequently fails.
    Show-PendingRenameReminder -NameState $after
    Save-RenameReceipt -TargetName $target
    Write-NamingLog "Verified rename to $target. Restart required=$($after.PendingRename)."
    if ($after.PendingRename) { exit 3010 }
    exit 0
} catch {
    if (Get-Command Write-NamingLog -ErrorAction SilentlyContinue) { Write-NamingLog "FAILED: $($_.Exception.Message)" }
    [Console]::Error.WriteLine("Computer rename failed: " + $_.Exception.Message)
    exit 1
}
