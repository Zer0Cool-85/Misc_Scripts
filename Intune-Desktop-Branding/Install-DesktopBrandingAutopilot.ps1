<# DesktopBranding for Windows Autopilot device ESP. Use classic Autopilot, x64
   native Windows PowerShell 5.1, device-targeted Required Win32 app, System,
   selected in the ESP blocking app list. Device enrollment stages the defaults.
   Each new profile consumes one HKCU RunOnce at its first desktop to apply them.
   Build on your packaging computer (no elevation or network needed):
     .\Install-DesktopBrandingAutopilot.ps1 -Mode Build -ThemeFile .\Theme\Custom.theme -WallpaperFile .\Wallpaper\Company.jpg -LockscreenFile .\Lockscreen\CompanyLock.jpg -OutputScript .\ESP\Install-DesktopBrandingAutopilot.ps1
   Package only the resulting script. Device command: powershell.exe -NoProfile
   -ExecutionPolicy Bypass -File .\Install-DesktopBrandingAutopilot.ps1 -Mode Stage
   From IME use %SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe.
   Detection (64-bit): HKLM\SOFTWARE\Company\DesktopBrandingAutopilot,
   REG_SZ Revision = ESP-1. Uninstall command: same host and file, -Mode Unstage.
   Unstage cancels future first-logon application and keeps assets in use.
   The device stage rejects a completed OOBE. Target Autopilot devices only.
   See README.md in the DesktopBranding download for setup and pilot steps. #>
[CmdletBinding()]
param(
    [ValidateSet('Build','Stage','FirstLogon','Unstage')][string]$Mode='Stage',
    [string]$ThemeFile, [string]$WallpaperFile, [string]$LockscreenFile, [string]$OutputScript
)
$ErrorActionPreference='Stop'
$revision='ESP-1'
$embeddedPayload='' # Embedded branding
function Write-Log([string]$Message) {
    $line='{0:s} {1}' -f (Get-Date),$Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogFile -Value $line
}
function Build-Standalone {
    foreach ($path in @($ThemeFile,$WallpaperFile,$LockscreenFile)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Supply existing theme, wallpaper and lock-screen files. Missing: $path" }
    }
    if ([IO.Path]::GetExtension($ThemeFile) -ine '.theme') { throw 'Supply a .theme file.' }
    $themeText=Get-Content -Raw -LiteralPath $ThemeFile
    if ((Get-DesktopBrandingThemeValue $themeText 'VisualStyles' 'ColorizationColor') -notmatch '^0x[0-9a-f]{8}$') {throw 'The theme needs [VisualStyles] ColorizationColor=0xAARRGGBB.'}
    if ($themeText -notmatch '(?im)^\s*\[Control Panel\\Desktop\]\s*$') { throw 'Missing [Control Panel\Desktop] in the theme.' }
    $payload=[ordered]@{Theme=$themeText; ThemeName=[IO.Path]::GetFileName($ThemeFile)}
    foreach ($asset in @('Wallpaper','Lockscreen')) {
        $path=if ($asset -eq 'Wallpaper') {$WallpaperFile} else {$LockscreenFile}
        $ext=[IO.Path]::GetExtension($path).ToLowerInvariant()
        if ($ext -notin '.jpg','.jpeg','.png','.bmp') { throw "Unsupported image extension $ext" }
        $bytes=[IO.File]::ReadAllBytes((Get-Item -LiteralPath $path).FullName)
        if ($bytes.Length -eq 0) { throw "Empty $asset image." }
        $payload[$asset]=[Convert]::ToBase64String($bytes)
        $payload[$asset+'Extension']=$ext
    }
    if (-not $OutputScript) { throw 'Supply -OutputScript for the generated standalone .ps1.' }
    $output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputScript)
    if ($output -ieq $PSCommandPath -or [IO.Path]::GetExtension($output) -ine '.ps1') { throw 'Choose a separate .ps1 output file.' }
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress)))
    $source=[IO.File]::ReadAllText($PSCommandPath)
    $pattern="(?m)^" + [regex]::Escape('$embeddedPayload=') + "'[A-Za-z0-9+/=]*' # Embedded branding"
    if ([regex]::Matches($source,$pattern).Count -ne 1) { throw 'Cannot identify the embedded payload field.' }
    $source=[regex]::Replace($source,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m) return '$embeddedPayload=' + "'$encoded' # Embedded branding"})
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
    [IO.File]::WriteAllText($output,$source,[Text.UTF8Encoding]::new($true))
    Write-Output "Built $output"
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

function Invoke-DefaultProfileEdit {
    param([scriptblock]$Edit)
    $profileList = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $defaultPath = [Environment]::ExpandEnvironmentVariables($profileList.Default)
    $hive = Join-Path $defaultPath 'NTUSER.DAT'
    $mount = 'DesktopBranding_' + [Guid]::NewGuid().ToString('N')
    $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
    $output = & $reg load "HKU\$mount" $hive 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Cannot load $hive ($LASTEXITCODE): $output" }
    try {
        $root = [Microsoft.Win32.Registry]::Users.OpenSubKey($mount, $true)
        if (-not $root) { throw "Cannot open loaded hive $mount" }
        try { & $Edit $root } finally { $root.Close() }
    } finally {
        for ($i=0; $i -lt 3; $i++) {
            $output = & $reg unload "HKU\$mount" 2>&1
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Milliseconds 500
        }
        if ($LASTEXITCODE -ne 0) { throw "Cannot unload HKU\$mount ($LASTEXITCODE): $output" }
    }
}
function Invoke-FirstDesktop($Config) {
    $ThemePath=$Config.Theme
    $LockScreenPath=$Config.Lockscreen
    $WallpaperPath=$Config.Wallpaper
    $themeText=Get-Content -Raw -LiteralPath $ThemePath
    $WallpaperStyle=Get-DesktopBrandingThemeValue $themeText 'Control Panel\Desktop' WallpaperStyle
    $TileWallpaper=Get-DesktopBrandingThemeValue $themeText 'Control Panel\Desktop' TileWallpaper
    if ($WallpaperStyle -notin '0','2','6','10','22') {$WallpaperStyle='10'}
    if ($TileWallpaper -notin '0','1') {$TileWallpaper='0'}
    $accent=Get-ThemeAccentData $ThemePath
    $PaletteHex=$accent.PaletteHex
    $AccentInt=$accent.AccentSignedInt
    $StartInt=$accent.StartSignedInt
    $DwmInt=$accent.DwmSignedInt
    # Opening the file is only a request; do not equate process launch with application.
    if (-not (Test-Path -LiteralPath $ThemePath -PathType Leaf)) { throw "Missing theme: $ThemePath" }
    Start-Process -FilePath $ThemePath -ErrorAction Stop
    Write-Log "Requested theme activation: $ThemePath"
    $themeSelected = $false
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        Start-Sleep -Seconds 1
        $themeState = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -ErrorAction SilentlyContinue
        $selected = [Environment]::ExpandEnvironmentVariables([string]$themeState.CurrentTheme)
        if ($selected -ieq $ThemePath) { $themeSelected = $true; break }
    }
    Write-Log "Theme-selection readback: $selected; exact source selected: $themeSelected"
    if (-not $themeSelected) {
        Write-Log 'WARNING: Windows did not confirm the source theme path. Wallpaper and accent will be applied explicitly; other theme components are not verified.'
    }

    # 2. Apply Lock Screen via WinRT API
    if (-not (Test-Path -LiteralPath $LockScreenPath -PathType Leaf)) { throw "Missing lock image: $LockScreenPath" }
    & {
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
        Write-Log "Applied lock screen image: $LockScreenPath"
    }

    # 3. Apply the activation preferences LAST, after the theme has been opened.
    # These are editable HKCU preferences, not policy settings.
    $personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if (-not (Test-Path $personalizeKey)) { New-Item -Path $personalizeKey -Force | Out-Null }
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
    if (-not (Test-Path $desktopKey)) { New-Item -Path $desktopKey -Force | Out-Null }
    New-ItemProperty -Path $desktopKey -Name WallpaperStyle -Value $WallpaperStyle -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktopKey -Name TileWallpaper -Value $TileWallpaper -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktopKey -Name AutoColorization -Value 0 -PropertyType DWord -Force | Out-Null
    $wallpapersKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    if (-not (Test-Path $wallpapersKey)) { New-Item -Path $wallpapersKey -Force | Out-Null }
    New-ItemProperty -Path $wallpapersKey -Name BackgroundType -Value 0 -PropertyType DWord -Force | Out-Null
    if (-not [DesktopBrandingRefresh]::SystemParametersInfoW(0x0014, 0, $WallpaperPath, 0x0003)) {
        throw "Wallpaper API failed; Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }
    Write-Log "Wallpaper applied through Windows API: $WallpaperPath"
    $palette = New-Object byte[] ($PaletteHex.Length / 2)
    for ($i = 0; $i -lt $palette.Length; $i++) { $palette[$i] = [Convert]::ToByte($PaletteHex.Substring($i * 2, 2), 16) }
    $accentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    $dwmKey = 'HKCU:\Software\Microsoft\Windows\DWM'
    if (-not (Test-Path $accentKey)) { New-Item -Path $accentKey -Force | Out-Null }
    if (-not (Test-Path $dwmKey)) { New-Item -Path $dwmKey -Force | Out-Null }
    New-ItemProperty -Path $accentKey -Name AccentPalette -Value $palette -PropertyType Binary -Force | Out-Null
    New-ItemProperty -Path $accentKey -Name AccentColorMenu -Value $AccentInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $accentKey -Name StartColorMenu -Value $StartInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $dwmKey -Name AccentColor -Value $AccentInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $dwmKey -Name ColorizationColor -Value $DwmInt -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $dwmKey -Name ColorizationAfterglow -Value $DwmInt -PropertyType DWord -Force | Out-Null
    [DesktopBrandingRefresh]::Notify()
    Start-Sleep -Seconds 2
    $actual = Get-ItemProperty -LiteralPath $personalizeKey -ErrorAction Stop
    Write-Log "Accent toggle readback: SystemUsesLightTheme=$($actual.SystemUsesLightTheme); ColorPrevalence=$($actual.ColorPrevalence)"
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
    Write-Log "Verified wallpaper: $wallpaperReadback; selected accent DWORD: $AccentInt"
    Write-Log 'Start/taskbar accent preferences saved and refresh requested. Visual rendering must be checked in the user session.'
}
function Set-TemplateValue($Root,[string]$Path,[string]$Name,[string]$Value) {
    $key=$Root.CreateSubKey($Path)
    try { $key.SetValue($Name,$Value,[Microsoft.Win32.RegistryValueKind]::String) } finally { $key.Close() }
}
function Stage-Branding {
    if ((Get-ItemProperty -LiteralPath $deviceKey -ErrorAction SilentlyContinue).Revision -eq $revision) {
        Write-Log 'This device stage is already recorded.'
        return
    }
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class DesktopBrandingOobe {
    [DllImport("kernel32.dll", ExactSpelling=true, SetLastError=true)]
    public static extern bool OOBEComplete(out bool completed);
}
'@
    $completed=$false
    if (-not [DesktopBrandingOobe]::OOBEComplete([ref]$completed)) {throw 'Windows could not report OOBE state.'}
    if ($completed) {throw 'OOBE has completed. Use the Company Portal app for this device.'}
    if (-not $embeddedPayload) {throw 'Package the output of -Mode Build to include your theme and images.'}
    $data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($embeddedPayload)) | ConvertFrom-Json
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $name=[IO.Path]::GetFileName([string]$data.ThemeName)
    if ($name -cne $data.ThemeName -or [IO.Path]::GetExtension($name) -ine '.theme') {throw 'Invalid embedded theme filename.'}
    $themePath=Join-Path $dir $name
    foreach ($asset in 'Wallpaper','Lockscreen') {
        $ext=$data.($asset+'Extension')
        if ($ext -notin '.jpg','.jpeg','.bmp','.png') {throw 'Invalid embedded image extension.'}
        [IO.File]::WriteAllBytes((Join-Path $dir ($asset+$ext)),[Convert]::FromBase64String($data.$asset))
    }
    $paper=Join-Path $dir ('Wallpaper'+$data.WallpaperExtension)
    $themeText=Set-DesktopBrandingThemeValue $data.Theme 'Control Panel\Desktop' Wallpaper $paper
    $themeText=Set-DesktopBrandingThemeValue $themeText VisualStyles AutoColorization 0
    $themeText=Set-DesktopBrandingThemeValue $themeText VisualStyles SystemMode Dark
    $themeText=[regex]::Replace($themeText,'(?ims)^\s*\[Slideshow\][^\r\n]*\r?\n.*?(?=^\s*\[|\z)','')
    [IO.File]::WriteAllText($themePath,$themeText,[Text.Encoding]::Unicode)
    $config=[ordered]@{Theme=$themePath;Wallpaper=$paper;Lockscreen=(Join-Path $dir ('Lockscreen'+$data.LockscreenExtension))}
    $config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'Branding.json') -Encoding UTF8
    Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    $command='"{0}" -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -Mode FirstLogon' -f $nativePS,$installedScript
    if ($command.Length -gt 260) {throw 'The RunOnce command exceeds the Windows limit.'}
    Invoke-DefaultProfileEdit {
        param($root)
        Set-TemplateValue $root 'Control Panel\Desktop' Wallpaper $paper
        Set-TemplateValue $root 'Software\Microsoft\Windows\CurrentVersion\Themes' CurrentTheme $themePath
        Set-TemplateValue $root $runOnceKey $runOnceName $command
    }
    if (-not (Test-Path $deviceKey)) {New-Item -Path $deviceKey -Force | Out-Null}
    New-ItemProperty -LiteralPath $deviceKey -Name Revision -Value $revision -PropertyType String -Force | Out-Null
    Write-Log "Device stage complete. New profiles will apply $themePath once at first desktop."
}
function Unstage-Branding {
    Invoke-DefaultProfileEdit {
        param($root)
        $key=$root.OpenSubKey($runOnceKey,$true)
        if ($key) {try {$key.DeleteValue($runOnceName,$false)} finally {$key.Close()}}
        foreach ($item in @(
            @{Path='Control Panel\Desktop';Name='Wallpaper';Fallback='Web\Wallpaper\Windows\img0.jpg'},
            @{Path='Software\Microsoft\Windows\CurrentVersion\Themes';Name='CurrentTheme';Fallback='Resources\Themes\aero.theme'}
        )) {
            $key=$root.OpenSubKey($item.Path,$true)
            if ($key) {
                try {
                    $current=[string]$key.GetValue($item.Name)
                    if ($current -and [IO.Path]::GetDirectoryName($current) -ieq $dir) {
                        $key.SetValue($item.Name,(Join-Path $env:SystemRoot $item.Fallback))
                    }
                } finally {$key.Close()}
            }
        }
    }
    if (Test-Path $deviceKey) {Remove-Item -LiteralPath $deviceKey -Recurse -Force}
    Write-Log 'Removed ESP provisioning defaults. Existing desktops may still reference the staged assets.'
}
try {
    if ($Mode -eq 'Build') { Build-Standalone; exit 0 }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {throw 'Use native Windows PowerShell.'}
    $dir=Join-Path $env:ProgramFiles 'DesktopBranding\Autopilot'
    $installedScript=Join-Path $dir 'FirstLogon.ps1'
    $nativePS=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $deviceKey='HKLM:\SOFTWARE\Company\DesktopBrandingAutopilot'
    $userKey='HKCU:\Software\Company\DesktopBrandingAutopilot'
    $runOnceKey='Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $runOnceName='DesktopBrandingAutopilot'
    if ($Mode -eq 'FirstLogon') {
        $logDir=Join-Path $env:LOCALAPPDATA 'DesktopBranding'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $script:LogFile=Join-Path $logDir 'Autopilot.log'
        if ((Get-Process -Id $PID).SessionId -eq 0 -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in 'S-1-5-18','S-1-5-19','S-1-5-20') {throw 'FirstLogon requires an interactive user.'}
        if ((Get-ItemProperty $deviceKey -ErrorAction SilentlyContinue).Revision -ne $revision) {Write-Log 'No active device stage.'; exit 0}
        if ((Get-ItemProperty $userKey -ErrorAction SilentlyContinue).Revision -eq $revision) {Write-Log 'This profile already applied the defaults.'; exit 0}
        $config=Get-Content -Raw -LiteralPath (Join-Path $dir 'Branding.json') | ConvertFrom-Json
        Invoke-FirstDesktop $config
        if (-not (Test-Path $userKey)) {New-Item -Path $userKey -Force | Out-Null}
        New-ItemProperty -LiteralPath $userKey -Name Revision -PropertyType String -Value $revision -Force | Out-Null
        Write-Log 'Applied the defaults for this profile.'
    } else {
        $logDir=Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $script:LogFile=Join-Path $logDir 'DesktopBranding-Autopilot.log'
        if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {throw 'Device stage and unstage require LocalSystem.'}
        if ($Mode -eq 'Stage') {Stage-Branding} else {Unstage-Branding}
    }
    exit 0
} catch {
    $detail="Mode $Mode failed at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    if ($script:LogFile) {try {Write-Log $detail} catch {}}
    [Console]::Error.WriteLine($detail)
    exit 1
}
