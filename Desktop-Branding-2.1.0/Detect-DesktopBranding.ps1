#requires -Version 5.1
# Intune custom detection: run as a 64-bit process.
# If CompanyFolder changes, update both ModMed references below.
$ErrorActionPreference = 'Stop'
try {
    $state = Get-ItemProperty `
        -Path 'HKLM:\SOFTWARE\ModMed\DesktopBrandingV2'
    if ($state.Version -ne '2.1.0') { exit 1 }
    $configPath = Join-Path $state.InstallPath 'Config.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($config.PackageVersion -ne '2.1.0') { exit 1 }
    if ($config.ThemeMode -notin @('Generated', 'CustomBranding', 'CustomPreserve')) { exit 1 }
    $requiredFiles = @(
        (Join-Path $state.InstallPath 'Apply-DesktopBranding.ps1'),
        (Join-Path $state.InstallPath 'Uninstall-DesktopBranding.ps1'),
        (Join-Path $state.InstallPath 'DesktopBranding.Theme.ps1'),
        $config.LockscreenPath
    )
    if ($config.ThemeMode -ne 'CustomPreserve') { $requiredFiles += $config.WallpaperPath }
    if ($config.ThemeMode -ne 'Generated') {
        $requiredFiles += (Join-Path $config.ThemePayloadPath $config.ThemeFile)
        $requiredFiles += @($config.ThemeFiles)
    }
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 1 }
    }
    $task = Get-ScheduledTask -TaskName 'ModMed-DesktopBrandingV2'
    if ($task.State -eq 'Disabled') { exit 1 }
    Write-Output 'Desktop Branding 2.1.0 installed'
    exit 0
}
catch { exit 1 }
