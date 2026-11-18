#requires -Version 5.1
<#
.SYNOPSIS
Stages editable desktop-branding defaults for current and future users.
.DESCRIPTION
Run as SYSTEM from an Intune Win32 app or as an elevated administrator.
Version 2.0.0. User initialization runs separately in an interactive session.
Keep DefaultsId unchanged to preserve completed users' personalization.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$CompanyFolder = 'ModMed',

    [ValidatePattern('^#?[0-9A-Fa-f]{6}$')]
    [string]$AccentHex = '#3F177E',

    [ValidatePattern('^[^\\/:*?"<>|]+\.(jpg|jpeg|png|bmp)$')]
    [string]$WallpaperImg = 'ModMed.jpg',

    [ValidatePattern('^[^\\/:*?"<>|]+\.(jpg|jpeg|png)$')]
    [string]$LockscreenImg = 'ModMedLock.jpg',

    # Change only when intentionally applying new defaults to users again.
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$DefaultsId = 'Defaults-v2'
)

$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and
    -not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:SystemRoot `
        'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $nativePowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $PSCommandPath `
        -CompanyFolder $CompanyFolder `
        -AccentHex $AccentHex `
        -WallpaperImg $WallpaperImg `
        -LockscreenImg $LockscreenImg `
        -DefaultsId $DefaultsId
    exit $LASTEXITCODE
}

$Version = '2.0.0'
$Root = Join-Path $env:ProgramFiles "$CompanyFolder\DesktopBrandingV2"
$MachineKey = "HKLM:\SOFTWARE\$CompanyFolder\DesktopBrandingV2"
$TaskName = "$CompanyFolder-DesktopBrandingV2"
$PowerShell = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'
$LogDirectory = Join-Path $env:ProgramData `
    'Microsoft\IntuneManagementExtension\Logs'
$LogFile = Join-Path $LogDirectory 'Install-DesktopBrandingV2.log'

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw 'Run this installer as SYSTEM or an elevated administrator.'
    }

    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    Write-Log "Starting Desktop Branding $Version."

    $wallpaperSource = Join-Path $PSScriptRoot "Wallpaper\$WallpaperImg"
    $lockscreenSource = Join-Path $PSScriptRoot "Lockscreen\$LockscreenImg"
    $applySource = Join-Path $PSScriptRoot 'Apply-DesktopBranding.ps1'
    $uninstallSource = Join-Path $PSScriptRoot 'Uninstall-DesktopBranding.ps1'
    foreach ($file in @(
        $wallpaperSource, $lockscreenSource, $applySource, $uninstallSource
    )) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required package file is missing: $file"
        }
    }

    # Standard users cannot modify the staged scripts/configuration.
    New-Item -Path $Root -ItemType Directory -Force | Out-Null
    New-Item -Path $MachineKey -Force | Out-Null
    Remove-ItemProperty -Path $MachineKey -Name Version `
        -ErrorAction SilentlyContinue

    $wallpaperTarget = Join-Path $Root (
        'Wallpaper' + [IO.Path]::GetExtension($WallpaperImg)
    )
    $lockscreenTarget = Join-Path $Root (
        'LockScreen' + [IO.Path]::GetExtension($LockscreenImg)
    )
    $applyTarget = Join-Path $Root 'Apply-DesktopBranding.ps1'
    Copy-Item -LiteralPath $wallpaperSource -Destination $wallpaperTarget -Force
    Copy-Item -LiteralPath $lockscreenSource -Destination $lockscreenTarget -Force
    Copy-Item -LiteralPath $applySource -Destination $applyTarget -Force
    Copy-Item -LiteralPath $uninstallSource `
        -Destination (Join-Path $Root 'Uninstall-DesktopBranding.ps1') -Force

    $config = [ordered]@{
        PackageVersion = $Version
        CompanyFolder  = $CompanyFolder
        DefaultsId     = $DefaultsId
        AccentHex      = $AccentHex.TrimStart('#').ToUpperInvariant()
        WallpaperPath  = $wallpaperTarget
        LockscreenPath = $lockscreenTarget
    }
    $configTemp = Join-Path $Root 'Config.tmp'
    $configPath = Join-Path $Root 'Config.json'
    $config | ConvertTo-Json |
        Set-Content -LiteralPath $configTemp -Encoding UTF8
    Move-Item -LiteralPath $configTemp -Destination $configPath -Force

    $actionArguments = (
        '-NoProfile -NonInteractive -STA -WindowStyle Hidden ' +
        '-ExecutionPolicy Bypass -File "{0}"'
    ) -f $applyTarget
    $action = New-ScheduledTaskAction `
        -Execute $PowerShell -Argument $actionArguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $trigger.Delay = 'PT30S'
    $groupPrincipal = New-ScheduledTaskPrincipal `
        -GroupId 'S-1-5-32-545' -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances Parallel `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -RestartCount 2 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger $trigger -Principal $groupPrincipal `
        -Settings $settings -Force | Out-Null

    # Detection describes staging, not successful application for every user.
    # Write Version last, once the other metadata is present.
    $metadata = [ordered]@{
        InstallPath = $Root
        DefaultsId  = $DefaultsId
        InstalledAt = (Get-Date).ToString('o')
        Version     = $Version
    }
    foreach ($entry in $metadata.GetEnumerator()) {
        New-ItemProperty -Path $MachineKey -Name $entry.Key `
            -Value $entry.Value -PropertyType String -Force | Out-Null
    }
    Write-Log 'Package staged and first-sign-in task registered.'

    # Resolve owners by SID, including Microsoft Entra ID accounts.
    $seen = @{}
    try {
        $explorers = @(Get-CimInstance Win32_Process `
            -Filter "Name='explorer.exe'")
    }
    catch {
        Write-Log "Could not enumerate current desktops: $($_.Exception.Message)"
        $explorers = @()
    }

    foreach ($process in $explorers) {
        if ($process.SessionId -le 0) { continue }
        try {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            if ($owner.ReturnValue -ne 0 -or -not $owner.Sid) { continue }
            $sid = [string]$owner.Sid
            if ($seen.ContainsKey($sid)) { continue }
            $seen[$sid] = $true
            $userPrincipal = New-ScheduledTaskPrincipal `
                -UserId $sid -LogonType Interactive -RunLevel Limited
            # On-demand only; retained for diagnostics until uninstall.
            $nowTaskName = "$TaskName-Now-$sid"
            Register-ScheduledTask -TaskName $nowTaskName `
                -Action $action -Principal $userPrincipal `
                -Settings $settings -Force | Out-Null
            Start-ScheduledTask -TaskName $nowTaskName
            Write-Log "Queued user initialization for $sid."
        }
        catch {
            Write-Log (
                'Could not queue one current user; the logon task remains ' +
                "available. Error: $($_.Exception.Message)"
            )
        }
    }

    Write-Log 'Installation complete. User application is tracked separately.'
    exit 0
}
catch {
    $message = $_.Exception.ToString()
    if (Test-Path -LiteralPath $LogDirectory) {
        Add-Content -LiteralPath $LogFile -Value "ERROR: $message" `
            -ErrorAction SilentlyContinue
    }
    [Console]::Error.WriteLine($message)
    exit 1
}
