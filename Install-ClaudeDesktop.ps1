#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions Claude.msix and records deployment diagnostics.
.DESCRIPTION
    Place this script beside Claude.msix and deploy the folder as an Intune
    Win32 app with Install behavior set to System. Use native 64-bit Windows
    PowerShell 5.1 on 64-bit Windows:

    %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Install-Claude.ps1"

    Sysnative is for launching from Intune's 32-bit install-command context.
    For manual testing, use an elevated Windows PowerShell 5.1 (64-bit) window.

    Each attempt writes to C:\ProgramData\ClaudeDeploy\<timestamp>-<process-id>:
      Install.log          - Transcript, execution context and package SHA256.
      Provisioning.log     - DISM provisioning log, if provisioning is reached.
      Error.txt            - Full exception details, on failure.
      AppXDeployment.txt   - Deployment events from the attempt, when available.

    Returns 0 when provisioning completes; returns 1 on failure. The detailed
    Windows error is recorded locally rather than being used as an Intune exit
    code. This script does not change Intune detection rules, uninstall existing
    versions, enable Windows features, or alter application-control policies.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PackageName = 'Claude.msix'
$PackagePath = Join-Path -Path $PSScriptRoot -ChildPath $PackageName
$StartedAt = Get-Date
$AttemptName = '{0}-{1}' -f $StartedAt.ToString('yyyyMMdd-HHmmss'), $PID
$LogRoot = Join-Path -Path $env:ProgramData -ChildPath 'ClaudeDeploy'
$LogDirectory = Join-Path -Path $LogRoot -ChildPath $AttemptName
$ExitCode = 1
$TranscriptStarted = $false

try {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    Start-Transcript -Path (Join-Path $LogDirectory 'Install.log') -Force | Out-Null
    $TranscriptStarted = $true

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    Write-Host "Identity: $($Identity.Name)"
    Write-Host "PowerShell: $($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition)"
    Write-Host "64-bit OS: $([Environment]::Is64BitOperatingSystem)"
    Write-Host "64-bit process: $([Environment]::Is64BitProcess)"
    Write-Host "OS version: $([Environment]::OSVersion.Version)"
    Write-Host "Package path: $PackagePath"
    Write-Host "Log directory: $LogDirectory"

    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Run this script with Windows PowerShell 5.1 (powershell.exe).'
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw 'Run in native 64-bit Windows PowerShell. Use the Sysnative install command documented at the top of this script.'
    }
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required. Set Intune Install behavior to System, or use an elevated window for manual testing.'
    }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "Package not found: $PackagePath. Include Claude.msix beside this script in the .intunewin source folder."
    }

    $PackageFile = Get-Item -LiteralPath $PackagePath
    if ($PackageFile.Length -eq 0) {
        throw "Package is empty: $PackagePath"
    }
    Write-Host "Package size (bytes): $($PackageFile.Length)"
    Write-Host "Package SHA256: $((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash)"

    # Provision package device-wide for all users.
    $ProvisioningParameters = @{
        Online      = $true
        PackagePath = $PackagePath
        SkipLicense = $true
        Regions     = 'all'
        LogPath     = Join-Path $LogDirectory 'Provisioning.log'
        LogLevel    = 'WarningsInfo'
        ErrorAction = 'Stop'
    }
    Add-AppxProvisionedPackage @ProvisioningParameters | Format-List * | Out-Host
    Write-Host "Successfully provisioned $PackageName."
    $ExitCode = 0
}
catch {
    # Preserve the original error before attempting any diagnostic collection.
    $InstallError = $_
    $ErrorDetails = @(
        "Failed to provision $PackageName"
        ('Exception HRESULT: 0x{0:X8}' -f $InstallError.Exception.HResult)
        ($InstallError | Format-List * -Force | Out-String -Width 4096)
        'Exception and inner exception details:'
        $InstallError.Exception.ToString()
    ) -join [Environment]::NewLine
    Write-Host $ErrorDetails -ForegroundColor Red

    try {
        $ErrorDetails | Set-Content -LiteralPath (Join-Path $LogDirectory 'Error.txt') -Encoding UTF8
    }
    catch {
        Write-Host "Could not save Error.txt: $($_.Exception.Message)"
    }

    try {
        $Events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-AppXDeploymentServer/Operational'
            StartTime = $StartedAt.AddSeconds(-10)
            EndTime   = Get-Date
        } -ErrorAction Stop
        $Events | Sort-Object TimeCreated, RecordId |
            Select-Object TimeCreated, RecordId, Id, LevelDisplayName, Message |
            Format-List | Out-String -Width 4096 |
            Set-Content -LiteralPath (Join-Path $LogDirectory 'AppXDeployment.txt') -Encoding UTF8
    }
    catch {
        Write-Host "AppX events unavailable for this attempt: $($_.Exception.Message)"
    }

    Write-Host "Installation failed. Review logs in $LogDirectory"
    $ExitCode = 1
}
finally {
    if ($TranscriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
}

exit $ExitCode
