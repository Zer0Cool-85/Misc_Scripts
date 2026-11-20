#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
Preview or clear app-specific local IME records on a pilot PC.
.DESCRIPTION
Use the Win32 mobile app object's GUID from its Intune URL. Preview is the
default. Apply briefly stops a running IME, backs up matching entries, removes
those entries and starts IME again. Use between deployments on a test device.
Registry layout is an IME implementation detail and can vary by agent version.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$AppId,
    [guid]$ContextId,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if ($AppId -eq [guid]::Empty) { throw 'Supply the Intune Win32 app GUID.' }
if (-not [Environment]::Is64BitProcess) { throw 'Run in elevated 64-bit Windows PowerShell.' }

$win32Path = 'SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$appPattern = '^' + [regex]::Escape($AppId.ToString()) + '(?:_[0-9]+)?$'
$contextFilter = if ($PSBoundParameters.ContainsKey('ContextId')) { $ContextId.ToString() }
function Get-AppCacheTargets {
    param($Root)
    foreach ($context in $Root.GetSubKeyNames()) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParseExact($context,'D',[ref]$parsed)) { continue }
        if ($contextFilter -and $context -ine $contextFilter) { continue }
        $userKey = $Root.OpenSubKey($context)
        if (!$userKey) { continue }
        try {
            foreach ($key in $userKey.GetSubKeyNames()) {
                if ($key -imatch $appPattern) {
                    [pscustomobject]@{Kind='Key'; Parent=$context; Name=$key}
                }
            }
            $grs = $userKey.OpenSubKey('GRS')
            if (!$grs) { continue }
            try {
                foreach ($hash in $grs.GetSubKeyNames()) {
                    $bucket = $grs.OpenSubKey($hash)
                    if (!$bucket) { continue }
                    try {
                        $path = "$context\GRS\$hash"
                        foreach ($value in $bucket.GetValueNames()) {
                            if ($value -imatch $appPattern) {
                                [pscustomobject]@{Kind='Value'; Parent=$path; Name=$value}
                            }
                        }
                        foreach ($child in $bucket.GetSubKeyNames()) {
                            if ($child -imatch $appPattern) {
                                [pscustomobject]@{Kind='Key'; Parent=$path; Name=$child}
                            }
                        }
                    } finally { $bucket.Dispose() }
                }
            } finally { $grs.Dispose() }
        } finally { $userKey.Dispose() }
    }
}

$hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry64')
$root = $null
$resumeIme = $false
try {
    $root = $hklm.OpenSubKey($win32Path)
    if (!$root) { Write-Host 'No local IME Win32Apps key. Use Company Portal > Settings > Sync.'; return }
    $plan = @(Get-AppCacheTargets $root)
    if (!$plan.Count) { Write-Host "No exact app entries found for $AppId. Use Company Portal > Settings > Sync and check the app GUID in AppWorkload.log."; return }
    $plan | Format-Table -Wrap -AutoSize | Out-Host
    if (!$Apply) { Write-Host 'Preview only. Add -Apply to remove these app records on this test PC.'; return }

    $ime = Get-Service -Name IntuneManagementExtension
    if ($ime.Status -ne 'Running') { throw 'Run when the IntuneManagementExtension service is running and the device has no active install.' }
    $resumeIme = $true
    Stop-Service -Name $ime.Name -ErrorAction Stop
    $ime.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
    $plan = @(Get-AppCacheTargets $root)
    if (!$plan.Count) { Write-Host 'Entries were cleared before reset.'; return }

    $backup = Join-Path $env:LOCALAPPDATA ('IntunePilotBackups\' + $AppId + '\' + [guid]::NewGuid())
    $null = New-Item $backup -ItemType Directory -Force
    Write-Host "Backup directory: $backup"
    $reg = Join-Path $env:WINDIR 'System32\reg.exe'
    $i = 0
    $manifest = foreach ($entry in $plan) {
        $i++
        $file = if ($entry.Kind -eq 'Key') { "$i.reg" } else { "$i.clixml" }
        $destination = Join-Path $backup $file
        if ($entry.Kind -eq 'Key') {
            $fullKey = "HKEY_LOCAL_MACHINE\$win32Path\$($entry.Parent)\$($entry.Name)"
            & $reg export $fullKey $destination /y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Export failed for $fullKey. Reset aborted before deletion." }
        } else {
            $parentKey = $root.OpenSubKey($entry.Parent)
            try {
                [pscustomobject]@{
                    Path = "HKEY_LOCAL_MACHINE\$win32Path\$($entry.Parent)"
                    Name = $entry.Name
                    Kind = $parentKey.GetValueKind($entry.Name).ToString()
                    Data = $parentKey.GetValue($entry.Name,$null,'DoNotExpandEnvironmentNames')
                } | Export-Clixml -LiteralPath $destination
            } finally { $parentKey.Dispose() }
        }
        [pscustomobject]@{Kind=$entry.Kind; Parent=$entry.Parent; Name=$entry.Name; BackupFile=$file}
    }
    $manifest | Export-Csv (Join-Path $backup 'manifest.csv') -NoTypeInformation
    foreach ($entry in $plan) {
        $parentKey = $root.OpenSubKey($entry.Parent,$true)
        try {
            if ($entry.Kind -eq 'Key') { $parentKey.DeleteSubKeyTree($entry.Name,$false) }
            else { $parentKey.DeleteValue($entry.Name,$false) }
        } finally { $parentKey.Dispose() }
    }
    Write-Host "Cleared $($plan.Count) records for $AppId."
} finally {
    if ($root) { $root.Dispose() }
    $hklm.Dispose()
    if ($resumeIme) {
        Start-Service -Name IntuneManagementExtension -ErrorAction Stop
        Write-Host 'IME started. Check AppWorkload.log for the app GUID and a new evaluation timestamp.'
    }
}
