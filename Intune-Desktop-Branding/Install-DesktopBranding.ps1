<#
.SYNOPSIS
    Deploys and applies a pre-configured Windows theme, accent color, desktop wallpaper, and lock screen image
    without restricting user personalization.

.DESCRIPTION
    Designed to run in the SYSTEM context via an Intune Win32 app (during Autopilot or on-demand/required deployments).
    Unlike PersonalizationCSP or GPO policies, this script sets corporate branding as the initial configuration while
    leaving Windows Settings unlocked so end users can still customize their device later.

    Execution workflow:
    1. Copies wallpaper and lock screen images into C:\Windows\Web\Wallpaper\<CompanyFolder>\.
    2. Copies the .theme file into C:\Windows\Resources\OEM Themes\.
    3. Mounts C:\Users\Default\NTUSER.DAT to set the theme as the default for any future user profiles.
    4. Detects if a user is currently signed into an active desktop session and triggers a temporary interactive
       Scheduled Task to apply the .theme file and set the lock screen via Windows Runtime (WinRT) APIs.

.PARAMETER CompanyFolder
    Optional. The subfolder name created inside C:\Windows\Web\Wallpaper\ where the wallpaper and lock screen
    images are stored. Aliased as -Location. Defaults to "Company".

.PARAMETER WallpaperImg
    Optional. The filename of the desktop wallpaper image located in the package's .\Wallpaper\ subfolder.
    Defaults to "Company.jpg".

.PARAMETER LockscreenImg
    Optional. The filename of the lock screen image located in the package's .\Lockscreen\ subfolder.
    Defaults to "CompanyLock.jpg".

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1

    Copies images to C:\Windows\Web\Wallpaper\Company\ and the .theme file to C:\Windows\Resources\OEM Themes\,
    configures the default user hive, and applies the theme and lock screen (CompanyLock.jpg) to the active user.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -LockscreenImg "Lock2026.jpg"

    Uses the default "Company" folder under C:\Windows\Web\Wallpaper\ and applies Lock2026.jpg as the lock screen.

.NOTES
    Prerequisite:
    The deployed .theme copy is updated to reference the staged wallpaper.
    Its [VisualStyles] section must specify the intended ColorizationColor=0xAARRGGBB.

    Required Win32 Source Folder Structure (prior to running IntuneWinAppUtil.exe):
    ├── Install-DesktopBranding.ps1
    ├── Lockscreen\
    │   └── CompanyLock.jpg
    ├── Theme\
    │   └── Custom.theme
    └── Wallpaper\
        └── Company.jpg

    Intune Win32 App Deployment Settings:
    - Install behavior:   System
    - Install command:    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1
    - Uninstall command:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1
    - Detection rule:     64-bit HKLM\SOFTWARE\Company\DesktopBranding: Revision equals ThemeApply-1

    Log File Location:
    %ProgramData%\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Alias("Location")]
    [string]$CompanyFolder = "Company",
    [string]$WallpaperImg = "Company.jpg",
    [string]$LockscreenImg = "CompanyLock.jpg"
)

# === GLOBAL VARIABLES ===
$script:ThemeDir       = Join-Path -Path $env:SystemRoot -ChildPath "Resources\OEM Themes"
$script:ImageDir       = Join-Path -Path $env:SystemRoot -ChildPath "Web\Wallpaper\$CompanyFolder"
$script:WallpaperPath  = Join-Path -Path $script:ImageDir -ChildPath $WallpaperImg
$script:LockscreenPath = Join-Path -Path $script:ImageDir -ChildPath $LockscreenImg
$script:LogFile        = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log"

# Ensure log directory exists
$logDir = Split-Path $script:LogFile
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# ==================== LOGGING ====================
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"  { Write-Host $logLine -ForegroundColor Gray }
        "WARN"  { Write-Warning $Message }
        "ERROR" { Write-Error $Message }
    }

    try { Add-Content -Path $script:LogFile -Value $logLine }
    catch { Write-Host "Failed to write to log file: $($_.Exception.Message)" }
}

# ==================== FUNCTIONS ====================
function Assert-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Script must be run as Administrator." "ERROR"
        throw "This script must be run from an elevated PowerShell session."
    }
    Write-Log "Confirmed running with Administrator privileges."
}

function Get-DesktopBrandingThemeValue {
    param([string]$Text, [string]$Section, [string]$Name)
    $inside = $false; $value = $null
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') { $inside = ($Matches[1] -ieq $Section); continue }
        if ($inside -and $line -match ('^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*?)\s*$')) { $value = $Matches[1] }
    }
    return $value
}

function Set-DesktopBrandingThemeValue {
    param([string]$Text, [string]$Section, [string]$Name, [string]$Value)
    $lines = [Collections.Generic.List[string]]::new()
    $inside = $false; $found = $false; $written = $false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*\[([^]]+)\]\s*$') {
            if ($inside -and -not $written) { $lines.Add("$Name=$Value"); $written = $true }
            $inside = ($Matches[1] -ieq $Section)
            if ($inside) { $found = $true }
        }
        if ($inside -and $line -match ('^\s*' + [regex]::Escape($Name) + '\s*=')) {
            $lines.Add("$Name=$Value"); $written = $true
        } else { $lines.Add($line) }
    }
    if (-not $found) { throw "Theme is missing required section [$Section]." }
    if (-not $written) { $lines.Add("$Name=$Value") }
    return ($lines -join "`r`n")
}

function Copy-BrandingMaterial {
    foreach ($source in @((Join-Path $PSScriptRoot "Wallpaper\$WallpaperImg"), (Join-Path $PSScriptRoot "Lockscreen\$LockscreenImg"))) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required image is missing: $source" }
    }
    Write-Log "Ensuring destination directories exist..."
    foreach ($dir in @($script:ThemeDir, $script:ImageDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Created directory: $dir"
        }
    }

    foreach ($ext in 'jpeg','jpg','png','bmp','gif') {
        if (Test-Path (Join-Path $PSScriptRoot "Wallpaper\*.$ext")) {
            Copy-Item -Path (Join-Path $PSScriptRoot "Wallpaper\*.$ext") -Destination "$script:ImageDir\" -Force -ErrorAction Stop | Out-Null
        }
        if (Test-Path (Join-Path $PSScriptRoot "Lockscreen\*.$ext")) {
            Copy-Item -Path (Join-Path $PSScriptRoot "Lockscreen\*.$ext") -Destination "$script:ImageDir\" -Force -ErrorAction Stop | Out-Null
        }
    }

    if (Test-Path (Join-Path $PSScriptRoot "Theme\*.theme")) {
        Copy-Item -Path (Join-Path $PSScriptRoot "Theme\*.theme") -Destination "$script:ThemeDir\" -Force -ErrorAction Stop | Out-Null
    }

    $sourceThemes = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Theme\*.theme') -ErrorAction Stop)
    if ($sourceThemes.Count -ne 1) { throw 'Place exactly one .theme file in the package Theme folder.' }
    $copiedTheme = Get-Item -LiteralPath (Join-Path $script:ThemeDir $sourceThemes[0].Name) -ErrorAction Stop
    if (-not $copiedTheme) {
        Write-Log "No .theme file found in $script:ThemeDir after copy." "WARN"
        return $null
    }

    Write-Log "Branding materials copied to $script:ImageDir and $script:ThemeDir."
    return $copiedTheme.FullName
}

function Get-ThemeAccentData {
    param([string]$ThemePath)

    $text = Get-Content -LiteralPath $ThemePath -Raw -ErrorAction Stop
    $rawColor = Get-DesktopBrandingThemeValue $text 'VisualStyles' 'ColorizationColor'
    if ($rawColor -notmatch '^0[xX][0-9A-Fa-f]{8}$') {
        throw 'The supplied theme must specify [VisualStyles] ColorizationColor=0xAARRGGBB. No fallback color will be substituted.'
    }

    # Parse 0xAARRGGBB
    $clean = $rawColor -replace '^0[xX]', ''
    $a = [Convert]::ToByte($clean.Substring(0, 2), 16)
    $r = [Convert]::ToByte($clean.Substring(2, 2), 16)
    $g = [Convert]::ToByte($clean.Substring(4, 2), 16)
    $b = [Convert]::ToByte($clean.Substring(6, 2), 16)

    # Convert RGB -> HSL to build Windows' 8-entry AccentPalette (3 light tints, base, 3 dark shades, base)
    $rn = $r / 255.0; $gn = $g / 255.0; $bn = $b / 255.0
    $max = [Math]::Max($rn, [Math]::Max($gn, $bn))
    $min = [Math]::Min($rn, [Math]::Min($gn, $bn))
    $l = ($max + $min) / 2.0
    $h = 0.0; $s = 0.0

    if ($max -ne $min) {
        $d = $max - $min
        $s = if ($l -gt 0.5) { $d / (2.0 - $max - $min) } else { $d / ($max + $min) }
        switch ($max) {
            $rn { $h = (($gn - $bn) / $d + $(if ($gn -lt $bn) { 6 } else { 0 })) / 6.0 }
            $gn { $h = (($bn - $rn) / $d + 2.0) / 6.0 }
            $bn { $h = (($rn - $gn) / $d + 4.0) / 6.0 }
        }
    }

    function ConvertFrom-Hsl([double]$hue, [double]$sat, [double]$lum) {
        if ($sat -eq 0) {
            $v = [byte][Math]::Round($lum * 255)
            return @($v, $v, $v)
        }
        $q = if ($lum -lt 0.5) { $lum * (1 + $sat) } else { $lum + $sat - ($lum * $sat) }
        $p = 2 * $lum - $q
        $rgb = foreach ($t in @(($hue + 1.0/3.0), $hue, ($hue - 1.0/3.0))) {
            $tc = $t
            if ($tc -lt 0) { $tc += 1 }
            if ($tc -gt 1) { $tc -= 1 }
            if ($tc -lt 1.0/6.0) { $c = $p + ($q - $p) * 6 * $tc }
            elseif ($tc -lt 0.5) { $c = $q }
            elseif ($tc -lt 2.0/3.0) { $c = $p + ($q - $p) * (2.0/3.0 - $tc) * 6 }
            else { $c = $p }
            [byte][Math]::Round($c * 255)
        }
        return $rgb
    }

    $shadesLum = @(
        [Math]::Min(0.92, $l + (1.0 - $l) * 0.65),
        [Math]::Min(0.85, $l + (1.0 - $l) * 0.45),
        [Math]::Min(0.75, $l + (1.0 - $l) * 0.25),
        $l,
        [Math]::Max(0.08, $l * 0.78),
        [Math]::Max(0.05, $l * 0.58),
        [Math]::Max(0.03, $l * 0.38),
        $l
    )

    $paletteHex = ""
    $startRgb = @($r, $g, $b)
    for ($i = 0; $i -lt 8; $i++) {
        $rgb = if ($i -eq 3 -or $i -eq 7) { @($r, $g, $b) } else { ConvertFrom-Hsl $h $s $shadesLum[$i] }
        if ($i -eq 4) { $startRgb = $rgb }
        $paletteHex += "{0:x2}{1:x2}{2:x2}00" -f $rgb[0], $rgb[1], $rgb[2]
    }

    # COLORREF = 0x00BBGGRR (used by SetUserColorPreference); ABGR = 0xFFBBGGRR (registry DWORD)
    $colorRefUint  = ([uint32]$b -shl 16) -bor ([uint32]$g -shl 8) -bor [uint32]$r
    $accentAbgrHex = "0xFF{0:X2}{1:X2}{2:X2}" -f $b, $g, $r
    $startAbgrHex  = "0xFF{0:X2}{1:X2}{2:X2}" -f $startRgb[2], $startRgb[1], $startRgb[0]
    $dwmArgbHex    = "0x{0:X2}{1:X2}{2:X2}{3:X2}" -f $a, $r, $g, $b
    $hexColor      = "{0:X2}{1:X2}{2:X2}" -f $r, $g, $b

    Write-Log "Parsed theme accent color #$hexColor (COLORREF=0x$("{0:X6}" -f $colorRefUint), ABGR=$accentAbgrHex)."

    return @{
        ColorRefUint    = $colorRefUint
        PaletteHex      = $paletteHex
        AccentAbgrHex   = $accentAbgrHex
        StartAbgrHex    = $startAbgrHex
        DwmArgbHex      = $dwmArgbHex
        AccentSignedInt = [BitConverter]::ToInt32([byte[]]($r, $g, $b, 0xFF), 0)
        StartSignedInt  = [BitConverter]::ToInt32([byte[]]($startRgb[0], $startRgb[1], $startRgb[2], 0xFF), 0)
        DwmSignedInt    = [BitConverter]::ToInt32([byte[]]($b, $g, $r, $a), 0)
    }
}

function Set-FutureUserTheme {
    param(
        [string]$ThemePath,
        [hashtable]$AccentData
    )
    if (-not $ThemePath) { return }

    Write-Log "Setting default theme, accent color, and Start/taskbar color toggle for future user profiles..."
    try {
        reg load HKU\DefaultUser "C:\Users\Default\NTUSER.DAT" | Out-Null
        reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes" /v "CurrentTheme" /t REG_SZ /d "$ThemePath" /f | Out-Null
        reg add "HKU\DefaultUser\Control Panel\Desktop" /v "AutoColorization" /t REG_DWORD /d 0 /f | Out-Null

        # Enable Dark Windows mode + Show accent color on Start and taskbar
        reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "ColorPrevalence" /t REG_DWORD /d 1 /f | Out-Null

        if ($AccentData) {
            reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" /v "AccentPalette" /t REG_BINARY /d $AccentData.PaletteHex /f | Out-Null
            reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" /v "AccentColorMenu" /t REG_DWORD /d $AccentData.AccentAbgrHex /f | Out-Null
            reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" /v "StartColorMenu" /t REG_DWORD /d $AccentData.StartAbgrHex /f | Out-Null

            reg add "HKU\DefaultUser\Software\Microsoft\Windows\DWM" /v "AccentColor" /t REG_DWORD /d $AccentData.AccentAbgrHex /f | Out-Null
            reg add "HKU\DefaultUser\Software\Microsoft\Windows\DWM" /v "ColorizationColor" /t REG_DWORD /d $AccentData.DwmArgbHex /f | Out-Null
            reg add "HKU\DefaultUser\Software\Microsoft\Windows\DWM" /v "ColorizationAfterglow" /t REG_DWORD /d $AccentData.DwmArgbHex /f | Out-Null
            reg add "HKU\DefaultUser\Software\Microsoft\Windows\DWM" /v "EnableWindowColorization" /t REG_DWORD /d 1 /f | Out-Null
        }

        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        reg unload HKU\DefaultUser | Out-Null
        Write-Log "DefaultUser registry hive updated successfully."
    } catch {
        Write-Log "Failed to update DefaultUser registry: $($_.Exception.Message)" "ERROR"
    }
}

function Get-DesktopBrandingSession {
    # Discover session numbers only; never query or translate an Entra account.
    $sessions = @(Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -gt 0 } |
        Select-Object -ExpandProperty SessionId | Sort-Object -Unique)
    if ($sessions.Count -eq 0) { return 0 }
    if ($sessions.Count -gt 1) {
        throw "Multiple Explorer sessions found ($($sessions -join ', ')); cannot safely choose a desktop."
    }
    return [int]$sessions[0]
}

function Start-DesktopBrandingTask {
    param([string]$TaskName, [int]$SessionId)
    if ($SessionId -le 0) { throw 'A positive desktop session ID is required.' }
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($TaskName)
    # TASK_RUN_USE_SESSION_ID = 4. A null user selects the existing session user.
    $instance = $registered.RunEx($null, 4, $SessionId, $null)
    if ($null -eq $instance) { throw "Task Scheduler returned no instance for $TaskName." }
    Write-Log "Task $TaskName launched in session $SessionId; instance $($instance.InstanceGuid)."
}

function Invoke-ActiveUserTheme {
    param(
        [string]$ThemePath,
        [hashtable]$AccentData
    )

    $TargetSessionId = Get-DesktopBrandingSession
    if ($TargetSessionId -eq 0) {
        Write-Log "No Explorer desktop is present. Current-user step skipped."
        return
    }
    Write-Log "Preparing current-user helper for desktop session $TargetSessionId."
    $tempUserScript = Join-Path -Path $script:ThemeDir -ChildPath "Apply-UserTheme.ps1"
    $tempUserLog    = Join-Path -Path $env:ProgramData -ChildPath "Apply-UserTheme.log"
    if (Test-Path $tempUserLog) { Remove-Item -Path $tempUserLog -Force -ErrorAction SilentlyContinue }

    $UserScriptHeader = @"
`$ExpectedSessionId = $TargetSessionId
`$WallpaperPath = '$($script:WallpaperPath -replace "'", "''")'
`$WallpaperStyle = '$($script:WallpaperStyle)'
`$TileWallpaper = '$($script:TileWallpaper)'
`$PaletteHex = '$($AccentData.PaletteHex)'
`$AccentInt = $($AccentData.AccentSignedInt)
`$StartInt = $($AccentData.StartSignedInt)
`$DwmInt = $($AccentData.DwmSignedInt)
`$ThemePath      = '$($ThemePath -replace "'", "''")'
`$LockScreenPath = '$($script:LockscreenPath -replace "'", "''")'
`$UserLog        = '$($tempUserLog -replace "'", "''")'

"@

    $UserScriptBody = @'
$ErrorActionPreference = 'Stop'

function Write-UserLog($msg) {
    $line = "[{0}] [USER] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $UserLog -Value $line -ErrorAction SilentlyContinue
}

try {
    if ((Get-Process -Id $PID).SessionId -ne $ExpectedSessionId -or
        [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
        throw 'User helper did not start in the requested interactive user session.'
    }
    Write-UserLog "User-context script started in session $ExpectedSessionId."

    # Opening the file is only a request; do not equate process launch with application.
    if (-not (Test-Path -LiteralPath $ThemePath -PathType Leaf)) { throw "Missing theme: $ThemePath" }
    Start-Process -FilePath $ThemePath -ErrorAction Stop
    Write-UserLog "Requested theme activation: $ThemePath"
    $themeSelected = $false
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        Start-Sleep -Seconds 1
        $themeState = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -ErrorAction SilentlyContinue
        $selected = [Environment]::ExpandEnvironmentVariables([string]$themeState.CurrentTheme)
        if ($selected -ieq $ThemePath) { $themeSelected = $true; break }
    }
    Write-UserLog "Theme-selection readback: $selected; exact source selected: $themeSelected"
    if (-not $themeSelected) {
        Write-UserLog 'WARNING: Windows did not confirm the source theme path. Wallpaper and accent will be applied explicitly; other theme components are not verified.'
    }

    # 2. Apply Lock Screen via WinRT API
    if ($LockScreenPath -and (Test-Path $LockScreenPath)) {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]

        function Await($WinRtTask, $ResultType) {
            $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
            $netTask = $asTask.Invoke($null, @($WinRtTask))
            $netTask.Wait(-1) | Out-Null
            return $netTask.Result
        }
        function AwaitAction($WinRtAction) {
            $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
                $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and -not $_.IsGenericMethod
            })[0]
            $netTask = $asTask.Invoke($null, @($WinRtAction))
            $netTask.Wait(-1) | Out-Null
        }

        [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
        [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null

        $ImageFile = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($LockScreenPath)) ([Windows.Storage.StorageFile])
        AwaitAction ([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($ImageFile))
        Write-UserLog "Applied lock screen image: $LockScreenPath"
    }

    # 3. Apply the activation preferences LAST, after the theme has been opened.
    # These are editable HKCU preferences, not policy settings.
    $personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    New-Item -Path $personalizeKey -Force | Out-Null
    New-ItemProperty -Path $personalizeKey -Name 'SystemUsesLightTheme' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $personalizeKey -Name 'ColorPrevalence' -Value 1 -PropertyType DWord -Force | Out-Null
    # App mode remains controlled by the supplied theme; set the selected RGB explicitly below.

    if (-not ('DesktopBrandingRefresh' -as [type])) {
    Add-Type -TypeDefinition '
using System;
using System.Runtime.InteropServices;
public static class DesktopBrandingRefresh {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SystemParametersInfoW(uint action, uint parameter, string path, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr SendMessageTimeoutW(
        IntPtr hWnd, uint message, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
    public static void Notify() {
        UIntPtr result;
        SendMessageTimeoutW(new IntPtr(0xffff), 0x001A, UIntPtr.Zero,
            "ImmersiveColorSet", 0x0002, 200, out result);
    }
}
'
    }
    # Replace the old theme's wallpaper and selected accent, not just its toggle.
    if (-not (Test-Path -LiteralPath $WallpaperPath -PathType Leaf)) { throw "Missing wallpaper: $WallpaperPath" }
    $desktopKey = 'HKCU:\Control Panel\Desktop'
    New-Item -Path $desktopKey -Force | Out-Null
    New-ItemProperty -Path $desktopKey -Name WallpaperStyle -Value $WallpaperStyle -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktopKey -Name TileWallpaper -Value $TileWallpaper -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktopKey -Name AutoColorization -Value 0 -PropertyType DWord -Force | Out-Null
    $wallpapersKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    New-Item -Path $wallpapersKey -Force | Out-Null
    New-ItemProperty -Path $wallpapersKey -Name BackgroundType -Value 0 -PropertyType DWord -Force | Out-Null
    if (-not [DesktopBrandingRefresh]::SystemParametersInfoW(0x0014, 0, $WallpaperPath, 0x0003)) {
        throw "Wallpaper API failed; Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }
    Write-UserLog "Wallpaper applied through Windows API: $WallpaperPath"
    $palette = New-Object byte[] ($PaletteHex.Length / 2)
    for ($i = 0; $i -lt $palette.Length; $i++) { $palette[$i] = [Convert]::ToByte($PaletteHex.Substring($i * 2, 2), 16) }
    $accentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    $dwmKey = 'HKCU:\Software\Microsoft\Windows\DWM'
    New-Item -Path $accentKey -Force | Out-Null
    New-Item -Path $dwmKey -Force | Out-Null
    New-ItemProperty -Path $accentKey -Name AccentPalette -Value $palette -PropertyType Binary -Force | Out-Null
    New-ItemProperty -Path $accentKey -Name AccentColorMenu -Value $AccentInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $accentKey -Name StartColorMenu -Value $StartInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $dwmKey -Name AccentColor -Value $AccentInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $dwmKey -Name ColorizationColor -Value $DwmInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $dwmKey -Name ColorizationAfterglow -Value $DwmInt -PropertyType DWord -Force | Out-Null
    [DesktopBrandingRefresh]::Notify()
    Start-Sleep -Seconds 2
    $actual = Get-ItemProperty -LiteralPath $personalizeKey -ErrorAction Stop
    Write-UserLog "Accent toggle readback: SystemUsesLightTheme=$($actual.SystemUsesLightTheme); ColorPrevalence=$($actual.ColorPrevalence)"
    if ($actual.SystemUsesLightTheme -ne 0 -or $actual.ColorPrevalence -ne 1) {
        throw 'Windows did not retain the Start/taskbar accent preferences.'
    }
    $wallpaperReadback = (Get-ItemProperty -LiteralPath $desktopKey -ErrorAction Stop).Wallpaper
    $accentReadback = Get-ItemProperty -LiteralPath $accentKey -ErrorAction Stop
    $dwmReadback = Get-ItemProperty -LiteralPath $dwmKey -ErrorAction Stop
    if ($wallpaperReadback -ine $WallpaperPath -or $accentReadback.AccentColorMenu -ne $AccentInt -or
        $accentReadback.StartColorMenu -ne $StartInt -or $dwmReadback.AccentColor -ne $AccentInt -or
        $dwmReadback.ColorizationColor -ne $DwmInt -or
        [BitConverter]::ToString([byte[]]$accentReadback.AccentPalette) -ne [BitConverter]::ToString($palette)) {
        throw 'Wallpaper/accent readback differs from the deployed branding. Check user policy or concurrent theme changes.'
    }
    Write-UserLog "Verified wallpaper: $wallpaperReadback; selected accent DWORD: $AccentInt"
    Write-UserLog 'Start/taskbar accent preferences saved and refresh requested. Visual rendering must be checked in the user session.'
    Write-UserLog "User-context script completed."
    exit 0
} catch {
    Write-UserLog "ERROR: $($_.Exception.Message)"
    exit 1
}
'@

    ($UserScriptHeader + $UserScriptBody) | Set-Content -Path $tempUserScript -Encoding UTF8 -Force

    Write-Log "Triggering user-context Scheduled Task..."
    $TaskName = "ApplyOrgThemeTemp"
    $Action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempUserScript`""
    # Only the built-in local Users group is resolved; no Entra account lookup.
    $localUsers = ([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')).Translate(
        [Security.Principal.NTAccount]
    ).Value
    Write-Log "Registering $TaskName with local group $localUsers; target session $TargetSessionId."
    $Principal = New-ScheduledTaskPrincipal -GroupId $localUsers -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3)

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force -ErrorAction Stop | Out-Null
    $requestedAt = (Get-Date).AddSeconds(-1)
    Start-DesktopBrandingTask -TaskName $TaskName -SessionId $TargetSessionId
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 1
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
        $finished = ($taskInfo.LastRunTime -ge $requestedAt -and $task.State -notin @('Running', 'Queued'))
    } while (-not $finished -and $timer.Elapsed.TotalSeconds -lt 180)
    if (-not $finished) {
        throw "User task did not finish within 180 seconds. Task and helper retained for inspection: $TaskName"
    }
    if ($taskInfo.LastTaskResult -ne 0) {
        throw "User task failed with result $($taskInfo.LastTaskResult). Task/helper retained; user log: $tempUserLog"
    }

    # Merge user-context log lines into main Intune log
    if (Test-Path $tempUserLog) {
        Get-Content -Path $tempUserLog | Add-Content -Path $script:LogFile
        Remove-Item -Path $tempUserLog -Force -ErrorAction SilentlyContinue
    } else {
        Write-Log "User-context log was not created; verify Scheduled Task execution for session $TargetSessionId." "WARN"
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Path $tempUserScript -Force -ErrorAction SilentlyContinue
    Write-Log "Active user theme, accent color, and lock screen step finished."
}

# ==================== MAIN ====================
try {
    Write-Log "=== Script started ==="
    Assert-Admin
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Company\DesktopBranding' -Name Revision -ErrorAction SilentlyContinue
    $ThemeFileTarget = Copy-BrandingMaterial
    $AccentData      = Get-ThemeAccentData -ThemePath $ThemeFileTarget
    $themeText = Get-Content -LiteralPath $ThemeFileTarget -Raw -ErrorAction Stop
    $script:WallpaperStyle = Get-DesktopBrandingThemeValue $themeText 'Control Panel\Desktop' 'WallpaperStyle'
    $script:TileWallpaper = Get-DesktopBrandingThemeValue $themeText 'Control Panel\Desktop' 'TileWallpaper'
    if ($script:WallpaperStyle -notin @('0','2','6','10','22')) { $script:WallpaperStyle = '10' }
    if ($script:TileWallpaper -notin @('0','1')) { $script:TileWallpaper = '0' }
    # Update the deployed copy only. Keep its named theme, sounds/icons/cursors.
    $themeText = Set-DesktopBrandingThemeValue $themeText 'Control Panel\Desktop' 'Wallpaper' $script:WallpaperPath
    $themeText = Set-DesktopBrandingThemeValue $themeText 'VisualStyles' 'AutoColorization' '0'
    $themeText = Set-DesktopBrandingThemeValue $themeText 'VisualStyles' 'SystemMode' 'Dark'
    $themeText = [regex]::Replace($themeText, '(?ims)^\s*\[Slideshow\][^\r\n]*\r?\n.*?(?=^\s*\[|\z)', '')
    Set-Content -LiteralPath $ThemeFileTarget -Value $themeText -Encoding Unicode -ErrorAction Stop
    Write-Log "Prepared deployed theme: $ThemeFileTarget; wallpaper: $script:WallpaperPath"
    Set-FutureUserTheme -ThemePath $ThemeFileTarget -AccentData $AccentData
    Invoke-ActiveUserTheme -ThemePath $ThemeFileTarget -AccentData $AccentData

    # Write Intune detection registry key
    $RegPath = "HKLM:\SOFTWARE\Company\DesktopBranding"
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    New-ItemProperty -Path $RegPath -Name "Version" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "InstalledDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "Revision" -Value 'ThemeApply-1' -PropertyType String -Force | Out-Null
    Write-Log "=== Script completed successfully ==="
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    exit 1
}