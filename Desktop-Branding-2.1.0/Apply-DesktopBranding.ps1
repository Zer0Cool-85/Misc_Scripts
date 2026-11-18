#requires -Version 5.1
<#
.SYNOPSIS
Applies branding defaults once in the interactive user's own context.
.DESCRIPTION
Invoked by the scheduled tasks created by Install-DesktopBranding.ps1.
Requires Config.json and image payloads beside this installed script.
Successful components are not reapplied when an unfinished component retries.
Supports generated themes and custom themes with managed or preserved settings.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$LogFile = $null
$mutex = $null
$ownsMutex = $false

if ([Environment]::Is64BitOperatingSystem -and
    -not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:SystemRoot `
        'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $nativePowerShell -NoProfile -NonInteractive -STA `
        -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Set-Value {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [ValidateSet('String', 'DWord', 'Binary')]
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value `
        -PropertyType $Type -Force | Out-Null
}

function Test-Step {
    param([string]$Name)
    $value = Get-ItemPropertyValue -Path $StateKey -Name $Name `
        -ErrorAction SilentlyContinue
    return ($value -eq 1)
}

function Complete-Step {
    param([string]$Name)
    Set-Value -Path $StateKey -Name $Name -Value 1
    Write-Log "$Name completed."
}

function Test-AllSteps {
    foreach ($name in @(
        'ThemeApplied', 'WallpaperApplied', 'AccentApplied', 'LockscreenApplied'
    )) {
        if (-not (Test-Step $name)) { return $false }
    }
    return $true
}

function Test-SelectedTheme {
    param([switch]$AllowCachedCopy)
    $current = [string](
        Get-ItemProperty -Path `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' `
            -ErrorAction SilentlyContinue
    ).CurrentTheme
    if ([string]::IsNullOrWhiteSpace($current)) { return $false }
    $current = [Environment]::ExpandEnvironmentVariables($current).Trim('"')
    if ($current -ieq $ThemePath) { return $true }

    # Windows may copy the selected theme to another per-user theme file.
    if ($AllowCachedCopy -and (Test-Path -LiteralPath $current -PathType Leaf)) {
        $content = [Environment]::ExpandEnvironmentVariables(
            (Get-Content -LiteralPath $current -Raw)
        )
        $expected = [Environment]::ExpandEnvironmentVariables(
            (Get-Content -LiteralPath $ThemePath -Raw)
        )
        $expectedName = Get-BrandingThemeSetting $expected 'Theme' 'DisplayName'
        if ([string]::IsNullOrWhiteSpace($expectedName)) { return $false }
        foreach ($field in @(
            @('Theme', 'DisplayName'),
            @('Control Panel\Desktop', 'Wallpaper'),
            @('VisualStyles', 'Path'),
            @('VisualStyles', 'ColorizationColor')
        )) {
            $wanted = Get-BrandingThemeSetting $expected $field[0] $field[1]
            $actual = Get-BrandingThemeSetting $content $field[0] $field[1]
            if ($wanted -ine $actual) { return $false }
        }
        return $true
    }
    return $false
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $identity.User.Value
    $sessionId = (Get-Process -Id $PID).SessionId

    if (
        $sid -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20') -or
        $sessionId -eq 0 -or
        $env:USERNAME -ieq 'defaultuser0'
    ) {
        exit 0
    }

    $config = Get-Content -LiteralPath `
        (Join-Path $PSScriptRoot 'Config.json') -Raw | ConvertFrom-Json
    . (Join-Path $PSScriptRoot 'DesktopBranding.Theme.ps1')
    if (
        $config.CompanyFolder -notmatch '^[A-Za-z0-9_-]+$' -or
        $config.DefaultsId -notmatch '^[A-Za-z0-9_-]+$' -or
        $config.ThemeMode -notin @('Generated', 'CustomBranding', 'CustomPreserve') -or
        ($config.ThemeMode -ne 'CustomPreserve' -and
            $config.AccentHex -notmatch '^[0-9A-Fa-f]{6}$')
    ) {
        throw 'Invalid branding configuration.'
    }

    $StateKey = (
        'HKCU:\Software\{0}\DesktopBrandingV2\{1}' -f
        $config.CompanyFolder, $config.DefaultsId
    )
    if (Test-AllSteps) { exit 0 }

    $UserRoot = Join-Path $env:LOCALAPPDATA (
        '{0}\DesktopBrandingV2\{1}' -f
        $config.CompanyFolder, $config.DefaultsId
    )
    New-Item -Path $UserRoot -ItemType Directory -Force | Out-Null
    $LogFile = Join-Path $UserRoot 'Apply-DesktopBranding.log'

    # Coordinate install-time and logon tasks within this user session.
    $mutexName = 'Local\{0}-DesktopBrandingV2-{1}' -f
        $config.CompanyFolder, $config.DefaultsId
    $mutex = [Threading.Mutex]::new($false, $mutexName)
    try { $ownsMutex = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { exit 0 }
    if (Test-AllSteps) { exit 0 }

    Write-Log "Starting for $($identity.Name), SID $sid, session $sessionId."
    Write-Log "Theme mode: $($config.ThemeMode); source: $($config.ThemeFile)"
    $desktopReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $desktop = Get-Process -Name explorer -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $sessionId } |
            Select-Object -First 1
        if ($desktop) {
            $desktopReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $desktopReady) {
        throw 'Explorer is not ready. Initialization will retry.'
    }

    if (-not ('DesktopBrandingV2.Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace DesktopBrandingV2
{
    public static class Native
    {
        [DllImport("user32.dll",
            EntryPoint = "SystemParametersInfoW",
            CharSet = CharSet.Unicode,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SystemParametersInfo(
            uint action, uint parameter, string value, uint flags);

        [DllImport("user32.dll",
            EntryPoint = "SendMessageTimeoutW",
            CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessageTimeout(
            IntPtr window, uint message, UIntPtr wParam,
            string lParam, uint flags, uint timeout,
            out UIntPtr result);

        public static void Refresh()
        {
            UIntPtr result;
            IntPtr broadcast = new IntPtr(0xffff);
            SendMessageTimeout(
                broadcast, 0x001A, UIntPtr.Zero,
                "ImmersiveColorSet", 0x0022, 200, out result);
            SendMessageTimeout(
                broadcast, 0x031A, UIntPtr.Zero,
                null, 0x0022, 200, out result);
        }
    }
}
'@
    }

    $UserWallpaper = ''
    if ($config.ThemeMode -ne 'CustomPreserve') {
        $UserWallpaper = Join-Path $UserRoot (
            'Wallpaper' + [IO.Path]::GetExtension($config.WallpaperPath)
        )
    }
    $UserLockscreen = Join-Path $UserRoot (
        'LockScreen' + [IO.Path]::GetExtension($config.LockscreenPath)
    )
    $userThemeDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes'
    $ThemePath = Join-Path $userThemeDirectory (
        '{0}-{1}.theme' -f $config.CompanyFolder, $config.DefaultsId
    )
    $UserThemeAssets = Join-Path $UserRoot 'Theme'

    # Preserve each user's copies after uninstall.
    if (-not (Test-Step 'AssetsStaged')) {
        New-Item -Path $userThemeDirectory -ItemType Directory -Force | Out-Null
        if ($config.ThemeMode -ne 'CustomPreserve') {
            Copy-Item -LiteralPath $config.WallpaperPath `
                -Destination $UserWallpaper -Force
        }
        Copy-Item -LiteralPath $config.LockscreenPath `
            -Destination $UserLockscreen -Force
        $templateText = ''
        if ($config.ThemeMode -ne 'Generated') {
            if (Test-Path -LiteralPath $UserThemeAssets) {
                Remove-Item -LiteralPath $UserThemeAssets -Recurse -Force
            }
            Copy-Item -LiteralPath $config.ThemePayloadPath `
                -Destination $UserThemeAssets -Recurse -Force
            $templateText = Get-Content -LiteralPath `
                (Join-Path $UserThemeAssets $config.ThemeFile) -Raw
        }
        New-BrandingThemeText -Settings $config -ThemeText $templateText `
            -WallpaperPath $UserWallpaper -ThemeAssetsPath $UserThemeAssets |
            Set-Content -LiteralPath $ThemePath -Encoding Unicode
        Complete-Step 'AssetsStaged'
    }

    if (-not (Test-Step 'ThemeApplied')) {
        if (-not (Test-SelectedTheme)) {
            Write-Log "Requesting theme activation: $ThemePath"
            Start-Process -FilePath $ThemePath -ErrorAction Stop | Out-Null
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ($timer.Elapsed.TotalSeconds -lt 45) {
                if (Test-SelectedTheme -AllowCachedCopy) { break }
                Start-Sleep -Milliseconds 500
            }
            if (-not (Test-SelectedTheme -AllowCachedCopy)) {
                throw (
                    'Windows did not confirm the selected theme within 45 seconds. ' +
                    'See Personalization and this user log.'
                )
            }
        }
        Start-Sleep -Seconds 2
        Complete-Step 'ThemeApplied'
    }

    if ($config.ThemeMode -eq 'CustomPreserve') {
        # The theme owns wallpaper, slideshow, accent and light/dark choices.
        # These markers mean theme handling satisfied these components; no
        # package wallpaper or accent registry override was performed.
        if (-not (Test-Step 'WallpaperApplied')) {
            Write-Log 'Using the custom theme wallpaper/slideshow without overrides.'
            Complete-Step 'WallpaperApplied'
        }
        if (-not (Test-Step 'AccentApplied')) {
            Write-Log 'Using the custom theme color/mode settings without overrides.'
            Complete-Step 'AccentApplied'
        }
    }

    if (-not (Test-Step 'WallpaperApplied')) {
        Set-Value -Path 'HKCU:\Control Panel\Desktop' `
            -Name WallpaperStyle -Value $config.WallpaperStyle -Type String
        Set-Value -Path 'HKCU:\Control Panel\Desktop' `
            -Name TileWallpaper -Value $config.TileWallpaper -Type String
        Set-Value -Path `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' `
            -Name BackgroundType -Value 0
        $success = [DesktopBrandingV2.Native]::SystemParametersInfo(
            0x0014, 0, $UserWallpaper, 0x0003
        )
        if (-not $success) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Setting the wallpaper failed. Win32 error: $errorCode"
        }
        Complete-Step 'WallpaperApplied'
    }

    if (-not (Test-Step 'AccentApplied')) {
        $hex = [string]$config.AccentHex
        $r = [Convert]::ToByte($hex.Substring(0, 2), 16)
        $g = [Convert]::ToByte($hex.Substring(2, 2), 16)
        $b = [Convert]::ToByte($hex.Substring(4, 2), 16)
        $accentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
        $dwmKey = 'HKCU:\Software\Microsoft\Windows\DWM'
        $personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

        # Three tints, base color, and three darker shades. Preserve entry 8.
        # This is deterministic, not Windows' private palette algorithm.
        $palette = New-Object byte[] 32
        $existingPalette = (
            Get-ItemProperty -Path $accentKey -Name AccentPalette `
                -ErrorAction SilentlyContinue
        ).AccentPalette
        if ($existingPalette -is [byte[]] -and $existingPalette.Length -eq 32) {
            [Array]::Copy($existingPalette, 28, $palette, 28, 4)
        }
        else {
            $palette[28] = $r
            $palette[29] = $g
            $palette[30] = $b
            $palette[31] = 0
        }
        $rgb = @($r, $g, $b)
        $mixes = @(0.65, 0.45, 0.25, 0.0, -0.22, -0.42, -0.62)
        for ($index = 0; $index -lt 7; $index++) {
            for ($channel = 0; $channel -lt 3; $channel++) {
                $base = [double]$rgb[$channel]
                $mix = [double]$mixes[$index]
                $value = if ($mix -ge 0) {
                    $base + (255 - $base) * $mix
                }
                else { $base * (1 + $mix) }
                $palette[$index * 4 + $channel] = [byte][Math]::Round($value)
            }
            $palette[$index * 4 + 3] = 0
        }

        $accentInt = [BitConverter]::ToInt32([byte[]]@($r, $g, $b, 255), 0)
        $startInt = [BitConverter]::ToInt32(
            [byte[]]@($palette[16], $palette[17], $palette[18], 255), 0
        )
        $dwmInt = [BitConverter]::ToInt32(
            [byte[]]@($b, $g, $r, [byte]$config.DwmAlpha), 0
        )

        Set-Value -Path 'HKCU:\Control Panel\Desktop' `
            -Name AutoColorization -Value 0
        Set-Value -Path $personalizeKey -Name SystemUsesLightTheme -Value 0
        if ($null -ne $config.AppsUseLightTheme) {
            Set-Value -Path $personalizeKey -Name AppsUseLightTheme `
                -Value ([int]$config.AppsUseLightTheme)
        }
        Set-Value -Path $personalizeKey -Name ColorPrevalence -Value 1
        Set-Value -Path $accentKey -Name AccentPalette `
            -Value $palette -Type Binary
        Set-Value -Path $accentKey -Name AccentColorMenu -Value $accentInt
        Set-Value -Path $accentKey -Name StartColorMenu -Value $startInt
        Set-Value -Path $dwmKey -Name AccentColor -Value $accentInt
        Set-Value -Path $dwmKey -Name ColorizationColor -Value $dwmInt
        Set-Value -Path $dwmKey -Name ColorizationAfterglow -Value $dwmInt

        $readback = Get-ItemProperty -Path $accentKey
        if (
            [int]$readback.AccentColorMenu -ne $accentInt -or
            [int]$readback.StartColorMenu -ne $startInt -or
            [BitConverter]::ToString([byte[]]$readback.AccentPalette) -ne
                [BitConverter]::ToString($palette)
        ) {
            throw 'Accent registry verification failed.'
        }
        [DesktopBrandingV2.Native]::Refresh()
        Write-Log "Stored accent #$hex and requested a shell refresh."
        Complete-Step 'AccentApplied'
    }

    if (-not (Test-Step 'LockscreenApplied')) {
        # Preferences remain editable; no policy keys or CSP enforcement.
        $contentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Set-Value -Path $contentKey -Name RotatingLockScreenEnabled -Value 0
        Set-Value -Path $contentKey -Name RotatingLockScreenOverlayEnabled -Value 0
        Set-Value -Path `
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen' `
            -Name SlideshowEnabled -Value 0

        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
        [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null

        $operationMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object {
                $_.Name -eq 'AsTask' -and
                $_.IsGenericMethodDefinition -and
                $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
            } | Select-Object -First 1
        $actionMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object {
                $_.Name -eq 'AsTask' -and
                -not $_.IsGenericMethod -and
                $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
            } | Select-Object -First 1
        if (-not $operationMethod -or -not $actionMethod) {
            throw 'Could not resolve the WinRT asynchronous task adapters.'
        }

        $lockAttempt = Join-Path $UserRoot (
            'LockScreen-{0}{1}' -f
            [Guid]::NewGuid().ToString('N'),
            [IO.Path]::GetExtension($UserLockscreen)
        )
        Copy-Item -LiteralPath $UserLockscreen -Destination $lockAttempt
        $fileOperation = [Windows.Storage.StorageFile]::GetFileFromPathAsync(
            $lockAttempt
        )
        $fileTask = $operationMethod.MakeGenericMethod(
            [Windows.Storage.StorageFile]
        ).Invoke($null, @($fileOperation))
        if (-not $fileTask.Wait(30000)) {
            throw 'Timed out opening the lock-screen image.'
        }
        $storageFile = $fileTask.GetAwaiter().GetResult()
        $lockOperation = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync(
            $storageFile
        )
        $lockTask = $actionMethod.Invoke($null, @($lockOperation))
        if (-not $lockTask.Wait(30000)) {
            throw 'Timed out setting the lock-screen image.'
        }
        $lockTask.GetAwaiter().GetResult() | Out-Null
        Set-Value -Path $StateKey -Name LockscreenImage `
            -Value $lockAttempt -Type String
        Complete-Step 'LockscreenApplied'
    }

    if (-not (Test-AllSteps)) {
        throw 'One or more branding components remain incomplete.'
    }
    Set-Value -Path $StateKey -Name CompletedAt `
        -Value (Get-Date).ToString('o') -Type String
    Write-Log 'Initialization complete. Future runs will preserve user choices.'
    exit 0
}
catch {
    $message = $_.Exception.ToString()
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value "ERROR: $message" `
            -ErrorAction SilentlyContinue
    }
    [Console]::Error.WriteLine($message)
    exit 1
}
finally {
    if ($ownsMutex -and $mutex) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
