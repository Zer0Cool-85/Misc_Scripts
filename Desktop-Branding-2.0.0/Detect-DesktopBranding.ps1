#requires -Version 5.1
# Intune custom detection: run as a 64-bit process.
# If CompanyFolder changes, update both ModMed references below.
$ErrorActionPreference = 'Stop'
try {
    $state = Get-ItemProperty `
        -Path 'HKLM:\SOFTWARE\ModMed\DesktopBrandingV2'
    if ($state.Version -ne '2.0.0') { exit 1 }
    $configPath = Join-Path $state.InstallPath 'Config.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    foreach ($file in @(
        (Join-Path $state.InstallPath 'Apply-DesktopBranding.ps1'),
        (Join-Path $state.InstallPath 'Uninstall-DesktopBranding.ps1'),
        $config.WallpaperPath,
        $config.LockscreenPath
    )) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 1 }
    }
    $task = Get-ScheduledTask -TaskName 'ModMed-DesktopBrandingV2'
    if ($task.State -eq 'Disabled') { exit 1 }
    Write-Output 'Desktop Branding 2.0.0 installed'
    exit 0
}
catch { exit 1 }
