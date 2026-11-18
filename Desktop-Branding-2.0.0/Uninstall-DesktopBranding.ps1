#requires -Version 5.1
<#
.SYNOPSIS
Removes the V2 deployment mechanism while preserving user appearance.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$CompanyFolder = 'ModMed'
)

$ErrorActionPreference = 'Stop'
if ([Environment]::Is64BitOperatingSystem -and
    -not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:SystemRoot `
        'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $nativePowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $PSCommandPath -CompanyFolder $CompanyFolder
    exit $LASTEXITCODE
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw 'Run this uninstaller as SYSTEM or an elevated administrator.'
    }

    $taskName = "$CompanyFolder-DesktopBrandingV2"
    $root = Join-Path $env:ProgramFiles "$CompanyFolder\DesktopBrandingV2"
    $machineKey = "HKLM:\SOFTWARE\$CompanyFolder\DesktopBrandingV2"
    $tasks = @(Get-ScheduledTask -TaskPath '\' | Where-Object {
        $_.TaskName -eq $taskName -or $_.TaskName.StartsWith(
            "$taskName-Now-", [StringComparison]::OrdinalIgnoreCase
        )
    })

    foreach ($task in $tasks) {
        Disable-ScheduledTask -InputObject $task | Out-Null
        Stop-ScheduledTask -TaskName $task.TaskName -TaskPath '\' `
            -ErrorAction SilentlyContinue
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            $current = Get-ScheduledTask -TaskName $task.TaskName -TaskPath '\'
            if ($current.State -ne 'Running') { break }
            Start-Sleep -Seconds 1
        }
        if ($current.State -eq 'Running') {
            throw "Task is still running: $($task.TaskName)"
        }
        Unregister-ScheduledTask -TaskName $task.TaskName `
            -TaskPath '\' -Confirm:$false
    }

    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
    if (Test-Path -LiteralPath $machineKey) {
        Remove-Item -LiteralPath $machineKey -Recurse -Force
    }

    # Do not remove per-user preferences, image copies, themes or markers.
    Write-Output 'Desktop Branding deployment removed; user appearance preserved.'
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.ToString())
    exit 1
}
