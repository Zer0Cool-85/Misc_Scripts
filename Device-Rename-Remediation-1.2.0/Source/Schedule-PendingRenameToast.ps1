#requires -Version 5.1
# Optional SYSTEM/admin diagnostic entry point. Never renames or restarts the PC.
[CmdletBinding()]
param([switch]$ForceReminder)
$ErrorActionPreference = 'Stop'
$script:Component = 'ScheduleToast'
try {
    . (Join-Path $PSScriptRoot 'Naming.Common.ps1')
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    $state = Get-ComputerNameState
    if (-not $state.PendingRename) { Write-Output 'No computer rename is pending.'; exit 0 }
    Show-PendingRenameReminder -NameState $state -ForceReminder:$ForceReminder -ReportFailures
    Write-Output 'Scheduling check completed. See DeviceRenameRemediation.log for the queue result and the user Toast.log for display status.'
    exit 0
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
