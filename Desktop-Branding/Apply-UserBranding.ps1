<#
.SYNOPSIS
    Per-user half of the DesktopBranding package. Applies (or reverts) the corporate theme, wallpaper,
    accent color and lock screen for the signed-in user.

.DESCRIPTION
    Copied to %ProgramData%\DesktopBranding (with branding.json) by Install-DesktopBranding.ps1 and always run
    in the USER's context, never as SYSTEM:
      - immediately, through a one-shot scheduled task, for users whose desktop is up when the Win32 app installs
      - at first sign-in, through HKCU\...\RunOnce, which the install seeds in C:\Users\Default\NTUSER.DAT (new
        profiles) and in the hive of anyone signed in whose desktop hasn't started yet (Autopilot account-setup ESP)

    Everything is written as an ordinary user preference (no policy keys), so users can change it afterwards.

    The install and uninstall scripts also dot-source this file to reuse the accent/registry helpers.

.PARAMETER ConfigPath
    Path to branding.json. Defaults to the file next to this script.

.PARAMETER FirstLogon
    Waits for first-sign-in shell setup to settle before applying (used by the RunOnce entry).

.PARAMETER Revert
    Reverts each branding element the user has NOT changed since it was applied (used by the uninstall).

.PARAMETER RequireDesktop
    Exits without changes if Explorer isn't running in this session (used by the install/uninstall scheduled task,
    which starts in every signed-in user's session; sessions without a desktop are handled by RunOnce instead).

.NOTES
    Log: %LOCALAPPDATA%\DesktopBranding\Apply-UserBranding.log (also merged into the Intune log when launched by
    the install/uninstall scripts).
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'branding.json'),
    [switch]$FirstLogon,
    [switch]$Revert,
    [switch]$RequireDesktop
)

# =====================================================================================================
#  SHARED HELPERS (also used by Install-/Uninstall-DesktopBranding.ps1 via dot-sourcing)
# =====================================================================================================

function ConvertTo-BrandingDWord {
    # Registry DWORDs are written through .NET as Int32. Accepts 0..0xFFFFFFFF (or an already signed Int32).
    param([Parameter(Mandatory)]$Value)
    $unsigned = [uint32]([int64]$Value -band 4294967295)
    return [BitConverter]::ToInt32([BitConverter]::GetBytes($unsigned), 0)
}

function Join-BrandingColorBytes {
    # Packs four bytes (most significant first) into a UInt32, e.g. (0xFF, B, G, R) -> 0xFFBBGGRR.
    param([Parameter(Mandatory)][int[]]$Bytes)
    return [uint32]([int64]$Bytes[0] * 16777216 + [int64]$Bytes[1] * 65536 + [int64]$Bytes[2] * 256 + [int64]$Bytes[3])
}

function Set-BrandingRegValue {
    param(
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Root,
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind = [Microsoft.Win32.RegistryValueKind]::DWord
    )
    $key = $Root.CreateSubKey($SubKey)
    try {
        if ($Kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { $Value = ConvertTo-BrandingDWord $Value }
        $key.SetValue($Name, $Value, $Kind)
    } finally {
        $key.Close()
    }
}

function Get-BrandingRegValue {
    param(
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Root,
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$Name
    )
    $key = $Root.OpenSubKey($SubKey)
    if (-not $key) { return $null }
    try { return $key.GetValue($Name) } finally { $key.Close() }
}

function Remove-BrandingRegValue {
    param(
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Root,
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string[]]$Name
    )
    $key = $Root.OpenSubKey($SubKey, $true)
    if (-not $key) { return }
    try { foreach ($n in $Name) { $key.DeleteValue($n, $false) } } finally { $key.Close() }
}

function ConvertFrom-BrandingHsl {
    param([double]$H, [double]$S, [double]$L)
    if ($S -eq 0) {
        $v = [int][Math]::Round($L * 255)
        return @($v, $v, $v)
    }
    $q = if ($L -lt 0.5) { $L * (1 + $S) } else { $L + $S - ($L * $S) }
    $p = 2 * $L - $q
    foreach ($t in @(($H + 1 / 3), $H, ($H - 1 / 3))) {
        if ($t -lt 0) { $t += 1 }
        if ($t -gt 1) { $t -= 1 }
        $c = if ($t -lt 1 / 6) { $p + ($q - $p) * 6 * $t }
             elseif ($t -lt 0.5) { $q }
             elseif ($t -lt 2 / 3) { $p + ($q - $p) * (2 / 3 - $t) * 6 }
             else { $p }
        [int][Math]::Round($c * 255)
    }
}

function Get-BrandingAccentData {
    <#
        Builds every representation Windows uses for one accent color.
        Accepts '#RRGGBB', 'RRGGBB', or the .theme style '0xAARRGGBB' / '0XC43F177E' (alpha is ignored).
    #>
    param([Parameter(Mandatory)][string]$Color)

    $hex = $Color.Trim() -replace '^(#|0x)', ''
    if ($hex -notmatch '^([0-9A-Fa-f]{2})?[0-9A-Fa-f]{6}$') {
        throw "Invalid accent color '$Color'. Use #RRGGBB or 0xAARRGGBB."
    }
    if ($hex.Length -eq 8) { $hex = $hex.Substring(2) }

    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)

    # RGB -> HSL
    $rn = [double]$r / 255; $gn = [double]$g / 255; $bn = [double]$b / 255
    $max = [Math]::Max($rn, [Math]::Max($gn, $bn))
    $min = [Math]::Min($rn, [Math]::Min($gn, $bn))
    $l = ($max + $min) / 2
    $h = 0.0; $s = 0.0
    if ($max -ne $min) {
        $d = $max - $min
        $s = if ($l -gt 0.5) { $d / (2 - $max - $min) } else { $d / ($max + $min) }
        if ($max -eq $rn)     { $h = ($gn - $bn) / $d + $(if ($gn -lt $bn) { 6 } else { 0 }) }
        elseif ($max -eq $gn) { $h = ($bn - $rn) / $d + 2 }
        else                  { $h = ($rn - $gn) / $d + 4 }
        $h = $h / 6
    }

    # AccentPalette = 8 RGBA entries: 3 lighter tints, the accent, 3 darker shades, the accent again.
    # Entry 3 backs AccentColorMenu, entry 4 backs StartColorMenu (Start/taskbar background).
    $lums = @(
        [Math]::Min(0.92, $l + (1 - $l) * 0.65),
        [Math]::Min(0.85, $l + (1 - $l) * 0.45),
        [Math]::Min(0.75, $l + (1 - $l) * 0.25),
        -1,
        [Math]::Max(0.08, $l * 0.78),
        [Math]::Max(0.05, $l * 0.58),
        [Math]::Max(0.03, $l * 0.38),
        -1
    )
    $palette  = New-Object byte[] 32
    $swatches = New-Object 'System.Collections.Generic.List[int[]]'
    for ($i = 0; $i -lt 8; $i++) {
        [int[]]$rgb = if ($lums[$i] -lt 0) { @($r, $g, $b) } else { ConvertFrom-BrandingHsl -H $h -S $s -L $lums[$i] }
        $palette[$i * 4]     = [byte]$rgb[0]
        $palette[$i * 4 + 1] = [byte]$rgb[1]
        $palette[$i * 4 + 2] = [byte]$rgb[2]
        $palette[$i * 4 + 3] = [byte]0
        $swatches.Add($rgb)
    }
    $start = $swatches[4]

    return [pscustomobject]@{
        Hex               = '{0:X2}{1:X2}{2:X2}' -f $r, $g, $b
        Palette           = $palette                                                          # REG_BINARY
        AccentColorMenu   = Join-BrandingColorBytes @(0xFF, $b, $g, $r)                      # 0xFFBBGGRR
        StartColorMenu    = Join-BrandingColorBytes @(0xFF, $start[2], $start[1], $start[0]) # 0xFFBBGGRR
        ColorizationColor = Join-BrandingColorBytes @(0xC4, $r, $g, $b)                      # 0xAARRGGBB (DWM)
        AccentColorRef    = Join-BrandingColorBytes @(0, $b, $g, $r)                         # COLORREF 0x00BBGGRR
        StartColorRef     = Join-BrandingColorBytes @(0, $start[2], $start[1], $start[0])    # COLORREF 0x00BBGGRR
    }
}

function Set-BrandingProfileValues {
    <#
        Writes the color-mode and accent preferences into a user hive (HKCU, or the mounted Default User hive).
        These are the same values the Settings app writes, so the user can still change them.
    #>
    param(
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Root,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Accent
    )
    $dark = ($Config.WindowsMode -eq 'Dark')
    $titleBars = [bool]$Config.AccentOnTitleBars

    $personalize = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-BrandingRegValue $Root $personalize 'SystemUsesLightTheme' ([int](-not $dark))
    Set-BrandingRegValue $Root $personalize 'AppsUseLightTheme'    ([int]($Config.AppMode -eq 'Light'))
    # "Show accent color on Start and taskbar" - Windows only honours this in Dark Windows mode
    Set-BrandingRegValue $Root $personalize 'ColorPrevalence'      ([int]$dark)

    # Stop Windows from picking the accent from the wallpaper
    Set-BrandingRegValue $Root 'Control Panel\Desktop' 'AutoColorization' 0

    $accentKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    Set-BrandingRegValue $Root $accentKey 'AccentPalette'   $Accent.Palette 'Binary'
    Set-BrandingRegValue $Root $accentKey 'AccentColorMenu' $Accent.AccentColorMenu
    Set-BrandingRegValue $Root $accentKey 'StartColorMenu'  $Accent.StartColorMenu

    $dwm = 'Software\Microsoft\Windows\DWM'
    Set-BrandingRegValue $Root $dwm 'AccentColor'              $Accent.AccentColorMenu
    Set-BrandingRegValue $Root $dwm 'ColorizationColor'        $Accent.ColorizationColor
    Set-BrandingRegValue $Root $dwm 'ColorizationAfterglow'    $Accent.ColorizationColor
    # "Show accent color on title bars and window borders"
    Set-BrandingRegValue $Root $dwm 'ColorPrevalence'          ([int]$titleBars)
    Set-BrandingRegValue $Root $dwm 'EnableWindowColorization' ([int]$titleBars)
}

# =====================================================================================================
#  USER-CONTEXT FUNCTIONS
# =====================================================================================================

function Write-UserLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    if (-not $script:UserLogFile) {
        $dir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'DesktopBranding'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $script:UserLogFile = Join-Path -Path $dir -ChildPath 'Apply-UserBranding.log'
    }
    $line = '[{0}] [USER] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:UserLogFile -Value $line -ErrorAction SilentlyContinue
}

function Invoke-BrandingStep {
    # Runs one step in isolation so a failure in one area (e.g. lock screen) never skips the others.
    param([Parameter(Mandatory)][string]$StepName, [Parameter(Mandatory)][scriptblock]$StepAction)
    try {
        & $StepAction
        Write-UserLog "$StepName - OK"
    } catch {
        Write-UserLog "$StepName - FAILED: $($_.Exception.Message)" 'WARN'
    }
}

function Add-BrandingNativeType {
    if ('DesktopBranding.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace DesktopBranding {
    public static class Native {
        // uxtheme's private accent API (the one the Settings app uses). Two COLORREFs: Start color, accent color.
        [StructLayout(LayoutKind.Sequential)]
        public struct IMMERSIVE_COLOR_PREFERENCE {
            public uint crStartColor;
            public uint crAccentColor;
        }

        [DllImport("uxtheme.dll", EntryPoint = "#122", PreserveSig = true)]
        private static extern int SetUserColorPreference(ref IMMERSIVE_COLOR_PREFERENCE pref,
            [MarshalAs(UnmanagedType.Bool)] bool forceCommit);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
            uint flags, uint timeout, out UIntPtr result);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SystemParametersInfo(uint action, uint uiParam, string pvParam, uint winIni);

        public static int SetAccent(uint startColorRef, uint accentColorRef) {
            IMMERSIVE_COLOR_PREFERENCE pref = new IMMERSIVE_COLOR_PREFERENCE();
            pref.crStartColor  = startColorRef  & 0x00FFFFFF;
            pref.crAccentColor = accentColorRef & 0x00FFFFFF;
            return SetUserColorPreference(ref pref, true);
        }

        // WM_SETTINGCHANGE with a string lParam must be SENT (SendNotifyMessage/PostMessage can't marshal the string).
        public static void Broadcast(string area) {
            UIntPtr result;
            SendMessageTimeout(new IntPtr(0xFFFF), 0x001A, UIntPtr.Zero, area, 0x0002 /*SMTO_ABORTIFHUNG*/, 5000, out result);
        }

        public static bool SetWallpaper(string path) {
            // SPI_SETDESKWALLPAPER, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
            return SystemParametersInfo(0x0014, 0, path, 0x01 | 0x02);
        }
    }
}
'@
}

function Invoke-BrandingThemeFile {
    # Opening a .theme hands it to the Settings app, which applies it asynchronously. Wait until Windows reports it
    # as the current theme (and a little longer) so it can't overwrite the accent we set afterwards.
    param([Parameter(Mandatory)][string]$Path, [int]$TimeoutSeconds = 30)

    $hkcu = [Microsoft.Win32.Registry]::CurrentUser
    $themesKey = 'Software\Microsoft\Windows\CurrentVersion\Themes'
    $settingsBefore = @(Get-Process -Name SystemSettings -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

    Start-Process -FilePath $Path
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 1
        $current = Get-BrandingRegValue $hkcu $themesKey 'CurrentTheme'
        if ($current) { $current = [Environment]::ExpandEnvironmentVariables($current) }
    } until (($current -and ($current -ieq $Path)) -or ((Get-Date) -gt $deadline))

    if ($current -ieq $Path) { Write-UserLog "Windows reports CurrentTheme = $current" }
    else { Write-UserLog "Theme did not report as current within $TimeoutSeconds s (CurrentTheme = $current)." 'WARN' }

    Start-Sleep -Seconds 4   # theme engine keeps applying sub-settings briefly after CurrentTheme flips

    # Close only the Settings window this script opened, never one the user already had open
    Get-Process -Name SystemSettings -ErrorAction SilentlyContinue |
        Where-Object { $settingsBefore -notcontains $_.Id } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Initialize-BrandingWinRt {
    if ($script:BrandingAsTaskOp) { return }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $methods = [System.WindowsRuntimeSystemExtensions].GetMethods()
    $script:BrandingAsTaskOp = $methods | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $script:BrandingAsTaskAction = $methods | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
    } | Select-Object -First 1
    [void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    [void][Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime]
}

function Set-BrandingLockScreen {
    param([Parameter(Mandatory)][string]$Path)
    Initialize-BrandingWinRt
    $openTask = $script:BrandingAsTaskOp.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke(
        $null, @([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)))
    if (-not $openTask.Wait(30000)) { throw "Timed out opening $Path" }

    $setTask = $script:BrandingAsTaskAction.Invoke(
        $null, @([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($openTask.Result)))
    if (-not $setTask.Wait(30000)) { throw "Timed out setting lock screen image" }
}

function Get-BrandingLockScreenPath {
    try {
        Initialize-BrandingWinRt
        $uri = [Windows.System.UserProfile.LockScreen]::OriginalImageFile
        if ($uri -and $uri.IsFile) { return $uri.LocalPath }
    } catch { }
    return $null
}

function Invoke-BrandingApply {
    param([Parameter(Mandatory)]$Config)

    $hkcu   = [Microsoft.Win32.Registry]::CurrentUser
    $accent = Get-BrandingAccentData -Color $Config.AccentColor
    Write-UserLog ("Applying branding v{0} for {1}\{2}: accent #{3}, Windows mode {4}, app mode {5}." -f `
        $Config.Version, $env:USERDOMAIN, $env:USERNAME, $accent.Hex, $Config.WindowsMode, $Config.AppMode)

    # 1. Theme first, fully finished, so nothing it does can land after the accent
    if ($Config.ThemePath -and (Test-Path -LiteralPath $Config.ThemePath)) {
        Invoke-BrandingStep 'Apply .theme file' { Invoke-BrandingThemeFile -Path $Config.ThemePath }
    } else {
        Write-UserLog "Theme file not found ($($Config.ThemePath)); skipping theme." 'WARN'
    }

    # 2. Full accent set: palette + Start/accent menu colors + DWM + color mode + Start/taskbar toggle
    Invoke-BrandingStep 'Write accent, palette and color-mode preferences' {
        Set-BrandingProfileValues -Root $hkcu -Config $Config -Accent $accent
    }

    # 3. Same API the Settings app calls; commits the accent and notifies the shell
    Invoke-BrandingStep 'SetUserColorPreference' {
        Add-BrandingNativeType
        $hr = [DesktopBranding.Native]::SetAccent($accent.StartColorRef, $accent.AccentColorRef)
        if ($hr -ne 0) { throw ('HRESULT 0x{0:X8}' -f $hr) }
    }

    # 4. Wallpaper (the theme normally sets it; this covers a theme that failed to apply)
    if ($Config.WallpaperPath -and (Test-Path -LiteralPath $Config.WallpaperPath)) {
        Invoke-BrandingStep 'Set desktop wallpaper' {
            Add-BrandingNativeType
            if (-not [DesktopBranding.Native]::SetWallpaper($Config.WallpaperPath)) { throw 'SystemParametersInfo returned false.' }
        }
    }

    # 5. Tell Explorer, Start, taskbar and DWM to re-read colors
    Invoke-BrandingStep 'Broadcast ImmersiveColorSet' {
        Add-BrandingNativeType
        [DesktopBranding.Native]::Broadcast('ImmersiveColorSet')
        [DesktopBranding.Native]::Broadcast('WindowsThemeElement')
    }

    # 6. Lock screen
    if ($Config.LockScreenPath -and (Test-Path -LiteralPath $Config.LockScreenPath)) {
        Invoke-BrandingStep 'Set lock screen image' {
            Set-BrandingLockScreen -Path $Config.LockScreenPath
            # Picture mode rather than Windows Spotlight (user can switch back in Settings)
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
        }
    } else {
        Write-UserLog "Lock screen image not found ($($Config.LockScreenPath)); skipping." 'WARN'
    }

    # 7. Remember what was applied, so the uninstall only reverts what the user hasn't changed
    Invoke-BrandingStep 'Record applied branding' {
        $applied = Get-BrandingRegValue $hkcu 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu'
        if ($null -eq $applied) { $applied = $accent.AccentColorMenu }
        $marker = "Software\$($Config.CompanyFolder)\DesktopBranding"
        Set-BrandingRegValue $hkcu $marker 'AppliedVersion'  ([int]$Config.Version)
        Set-BrandingRegValue $hkcu $marker 'AccentColorMenu' $applied
        Set-BrandingRegValue $hkcu $marker 'AppliedOn'       (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') 'String'
    }

    Write-UserLog 'Branding apply finished.'
}

function Invoke-BrandingRevert {
    param([Parameter(Mandatory)]$Config)

    $hkcu   = [Microsoft.Win32.Registry]::CurrentUser
    $marker = "Software\$($Config.CompanyFolder)\DesktopBranding"
    $applied = Get-BrandingRegValue $hkcu $marker 'AccentColorMenu'
    if ($null -eq $applied) {
        Write-UserLog 'No branding marker for this user; nothing to revert.'
        return
    }

    $defaultTheme = Join-Path $env:SystemRoot 'Resources\Themes\aero.theme'
    $defaultWall  = Join-Path $env:SystemRoot 'Web\Wallpaper\Windows\img0.jpg'
    $defaultLock  = Join-Path $env:SystemRoot 'Web\Screen\img100.jpg'
    $imageDir     = [string]$Config.ImageDir

    $currentTheme  = Get-BrandingRegValue $hkcu 'Software\Microsoft\Windows\CurrentVersion\Themes' 'CurrentTheme'
    if ($currentTheme) { $currentTheme = [Environment]::ExpandEnvironmentVariables($currentTheme) }
    $currentAccent = Get-BrandingRegValue $hkcu 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu'
    $currentWall   = Get-BrandingRegValue $hkcu 'Control Panel\Desktop' 'Wallpaper'
    $currentLock   = Get-BrandingLockScreenPath

    $themeIsOurs  = [bool]($currentTheme -and $Config.ThemePath -and ($currentTheme -ieq $Config.ThemePath))
    $accentIsOurs = ($null -ne $currentAccent) -and ((ConvertTo-BrandingDWord $currentAccent) -eq (ConvertTo-BrandingDWord $applied))
    $wallIsOurs   = [bool]($currentWall -and $imageDir -and $currentWall.StartsWith($imageDir, [StringComparison]::OrdinalIgnoreCase))
    $lockIsOurs   = if ($currentLock) {
                        ($imageDir -and $currentLock.StartsWith($imageDir, [StringComparison]::OrdinalIgnoreCase)) -or
                        ($Config.LockScreenPath -and ((Split-Path $currentLock -Leaf) -ieq (Split-Path $Config.LockScreenPath -Leaf)))
                    } else { $accentIsOurs }   # can't read it back: assume untouched if the accent is untouched

    Write-UserLog "Revert check: theme=$themeIsOurs accent=$accentIsOurs wallpaper=$wallIsOurs lockscreen=$lockIsOurs"

    if ($themeIsOurs -and (Test-Path -LiteralPath $defaultTheme)) {
        Invoke-BrandingStep 'Apply stock aero.theme' {
            Invoke-BrandingThemeFile -Path $defaultTheme
            if ($currentWall -and -not $wallIsOurs) {
                Add-BrandingNativeType
                [void][DesktopBranding.Native]::SetWallpaper($currentWall)   # keep the user's own wallpaper
            }
        }
    }

    if ($accentIsOurs) {
        Invoke-BrandingStep 'Reset accent color to Windows default' {
            $stock = Get-BrandingAccentData -Color '#0078D4'
            $accentKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
            Set-BrandingRegValue $hkcu $accentKey 'AccentPalette'   $stock.Palette 'Binary'
            Set-BrandingRegValue $hkcu $accentKey 'AccentColorMenu' $stock.AccentColorMenu
            Set-BrandingRegValue $hkcu $accentKey 'StartColorMenu'  $stock.StartColorMenu
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\DWM' 'AccentColor'              $stock.AccentColorMenu
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\DWM' 'ColorizationColor'        $stock.ColorizationColor
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\DWM' 'ColorizationAfterglow'    $stock.ColorizationColor
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\DWM' 'ColorPrevalence'          0
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\DWM' 'EnableWindowColorization' 0
            Set-BrandingRegValue $hkcu 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'ColorPrevalence' 0
            Add-BrandingNativeType
            [void][DesktopBranding.Native]::SetAccent($stock.StartColorRef, $stock.AccentColorRef)
        }
    }

    if ($wallIsOurs -and -not $themeIsOurs -and (Test-Path -LiteralPath $defaultWall)) {
        Invoke-BrandingStep 'Reset wallpaper to Windows default' {
            Add-BrandingNativeType
            [void][DesktopBranding.Native]::SetWallpaper($defaultWall)
        }
    }

    Invoke-BrandingStep 'Broadcast ImmersiveColorSet' {
        Add-BrandingNativeType
        [DesktopBranding.Native]::Broadcast('ImmersiveColorSet')
        [DesktopBranding.Native]::Broadcast('WindowsThemeElement')
    }

    if ($lockIsOurs -and (Test-Path -LiteralPath $defaultLock)) {
        Invoke-BrandingStep 'Reset lock screen to Windows default' { Set-BrandingLockScreen -Path $defaultLock }
    }

    try { $hkcu.DeleteSubKeyTree($marker, $false) } catch { }
    Write-UserLog 'Branding revert finished.'
}

# =====================================================================================================
#  MAIN (skipped when this file is dot-sourced)
# =====================================================================================================
if ($MyInvocation.InvocationName -ne '.') {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        Write-Error 'Apply-UserBranding.ps1 must run in the user context, not as SYSTEM.'
        exit 2
    }
    try {
        if ($RequireDesktop) {
            $mySession = (Get-Process -Id $PID).SessionId
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession })) {
                Write-UserLog 'Desktop not running in this session; skipping (RunOnce applies it when the desktop starts).'
                exit 0
            }
        }
        if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config file not found: $ConfigPath" }
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

        if ($FirstLogon) {
            Write-UserLog 'First sign-in run; waiting for the shell to settle.'
            Start-Sleep -Seconds 15
        }

        if ($Revert) { Invoke-BrandingRevert -Config $config }
        else         { Invoke-BrandingApply  -Config $config }
        exit 0
    } catch {
        Write-UserLog "Fatal: $($_.Exception.Message)" 'ERROR'
        exit 1
    }
}
