<#
.SYNOPSIS
    Deploys a corporate Windows theme, wallpaper, accent color (shown on Start/taskbar) and lock screen as the
    starting configuration, without locking any of it down.

.DESCRIPTION
    Runs as SYSTEM from an Intune Win32 app, during Autopilot (device or account-setup ESP) or post-enrollment
    while a user is working. Nothing is written to policy keys, so users can change everything later in Settings.

    Execution workflow:
    1. Relaunches itself in 64-bit PowerShell (IME starts Win32 installs in 32-bit PowerShell).
    2. Copies the wallpaper and lock screen images to C:\Windows\Web\Wallpaper\<CompanyFolder>\.
    3. Copies the .theme to C:\Windows\Resources\OEM Themes\ and normalises that copy so it agrees with the
       script: Wallpaper path, AutoColorization=0, ColorizationColor, SystemMode and AppMode.
    4. Copies Apply-UserBranding.ps1 + branding.json to %ProgramData%\DesktopBranding (read-only for users).
    5. Default User hive: seeds the accent, palette, color mode, wallpaper and theme, and adds a RunOnce entry so
       every NEW profile runs Apply-UserBranding.ps1 once at first sign-in (Windows' first-logon setup otherwise
       resets the accent to blue).
    6. Signed-in users:
         - desktop running   -> applies now through a one-shot scheduled task that runs as the built-in Users
                                group (avoids Entra ID account-lookup failures in Task Scheduler)
         - desktop not ready -> (Autopilot account-setup ESP) adds the same RunOnce entry to their loaded hive
    7. Writes HKLM\SOFTWARE\<CompanyFolder>\DesktopBranding\Version for Intune detection.

.PARAMETER CompanyFolder
    Subfolder under C:\Windows\Web\Wallpaper\ for the images; also used for the registry key names.
    Aliased as -Location. Defaults to "Company".

.PARAMETER WallpaperImg
    Desktop wallpaper file name in the package's .\Wallpaper\ folder. Defaults to "Company.jpg".

.PARAMETER LockscreenImg
    Lock screen file name in the package's .\Lockscreen\ folder. Defaults to "CompanyLock.jpg".

.PARAMETER ThemeFile
    .theme file name in the package's .\Theme\ folder. Defaults to the first *.theme found there.

.PARAMETER AccentColor
    Accent color as #RRGGBB (e.g. "#3F177E"). Defaults to ColorizationColor from the .theme file.

.PARAMETER WindowsMode
    Dark or Light for Start/taskbar/system UI. Defaults to Dark. "Show accent color on Start and taskbar"
    only works in Dark, so it is turned on only when this is Dark.

.PARAMETER AppMode
    Dark or Light for apps. Defaults to Light.

.PARAMETER NoAccentOnTitleBars
    Don't turn on "Show accent color on title bars and window borders".

.PARAMETER Version
    Written to the detection key. Bump it (and the detection rule) to push a changed package.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -AccentColor "#3F177E" -LockscreenImg "Lock2026.jpg" -Version 2

.NOTES
    Win32 source folder (before IntuneWinAppUtil.exe):
    ├── Install-DesktopBranding.ps1
    ├── Uninstall-DesktopBranding.ps1
    ├── Apply-UserBranding.ps1
    ├── Lockscreen\CompanyLock.jpg
    ├── Theme\CompanyBrand.theme
    └── Wallpaper\Company.jpg

    Intune Win32 app settings:
    - Install behavior:   System
    - Install command:    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1
    - Uninstall command:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1
    - Detection rule:     Registry  HKEY_LOCAL_MACHINE\SOFTWARE\Company\DesktopBranding
                          Value name: Version   Detection method: Integer comparison   Operator: Greater than or equal to   Value: 1
                          Associated with a 32-bit app on 64-bit clients: No

    Logs:
    - %ProgramData%\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log  (includes user-task output)
    - %LOCALAPPDATA%\DesktopBranding\Apply-UserBranding.log                               (per user)
#>
[CmdletBinding()]
param(
    [Alias('Location')]
    [string]$CompanyFolder = 'Company',
    [string]$WallpaperImg = 'Company.jpg',
    [string]$LockscreenImg = 'CompanyLock.jpg',
    [string]$ThemeFile,
    [string]$AccentColor,
    [ValidateSet('Dark', 'Light')][string]$WindowsMode = 'Dark',
    [ValidateSet('Dark', 'Light')][string]$AppMode = 'Light',
    [switch]$NoAccentOnTitleBars,
    [int]$Version = 1
)

# === Relaunch in 64-bit PowerShell (IME runs Win32 app commands in 32-bit PowerShell) ===
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path -Path $env:SystemRoot -ChildPath 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $relaunchArgs = @()
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value.IsPresent) { $relaunchArgs += "-$($kv.Key)" } }
        else { $relaunchArgs += "-$($kv.Key)"; $relaunchArgs += [string]$kv.Value }
    }
    & $ps64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @relaunchArgs
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

# === GLOBAL VARIABLES ===
$script:ThemeDir     = Join-Path -Path $env:SystemRoot -ChildPath 'Resources\OEM Themes'
$script:ImageDir     = Join-Path -Path $env:SystemRoot -ChildPath "Web\Wallpaper\$CompanyFolder"
$script:AppDataDir   = Join-Path -Path $env:ProgramData -ChildPath 'DesktopBranding'
$script:UserScript   = Join-Path -Path $script:AppDataDir -ChildPath 'Apply-UserBranding.ps1'
$script:ConfigFile   = Join-Path -Path $script:AppDataDir -ChildPath 'branding.json'
$script:PsExe        = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:RunOnceName  = 'DesktopBranding'
$script:LogFile      = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log'

$logDir = Split-Path -Path $script:LogFile
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

# ==================== LOGGING ====================
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $script:LogFile -Value $line } catch { }
}

# ==================== FUNCTIONS ====================
function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must run as SYSTEM or from an elevated PowerShell session.'
    }
    Write-Log "Running as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) (64-bit: $([Environment]::Is64BitProcess))."
}

function Invoke-NativeTool {
    # Start-Process avoids PS 5.1 turning native stderr into terminating errors under ErrorActionPreference=Stop
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

function Remove-LegacyArtifacts {
    # Leftovers from the previous version of this package
    foreach ($task in 'ApplyOrgThemeTemp', 'RevertOrgThemeTemp') {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath (Join-Path $script:ThemeDir 'Apply-UserTheme.ps1') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $env:ProgramData 'Apply-UserTheme.log') -Force -ErrorAction SilentlyContinue
}

function Read-ThemeFile {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $encoding = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode }
                elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { New-Object Text.UTF8Encoding($true) }
                else { [Text.Encoding]::Default }
    $reader = New-Object IO.StreamReader($Path, $encoding, $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Close() }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.AddRange([string[]]($text -split "`r?`n"))
    return [pscustomobject]@{ Lines = $lines; Encoding = $encoding }
}

function Get-ThemeSectionRange {
    param($Lines, [string]$Section)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $end = $Lines.Count
    for ($j = $start + 1; $j -lt $Lines.Count; $j++) {
        if ($Lines[$j].Trim() -match '^\[.+\]$') { $end = $j; break }
    }
    return @($start, $end)
}

function Get-ThemeValue {
    param($Lines, [string]$Section, [string]$Key)
    $range = Get-ThemeSectionRange -Lines $Lines -Section $Section
    if (-not $range) { return $null }
    for ($i = $range[0] + 1; $i -lt $range[1]; $i++) {
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*?)\s*$") { return $Matches[1] }
    }
    return $null
}

function Set-ThemeValue {
    param($Lines, [string]$Section, [string]$Key, [string]$Value)
    $range = Get-ThemeSectionRange -Lines $Lines -Section $Section
    if (-not $range) {
        $Lines.Add('')
        $Lines.Add("[$Section]")
        $Lines.Add("$Key=$Value")
        return
    }
    for ($i = $range[0] + 1; $i -lt $range[1]; $i++) {
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $Lines[$i] = "$Key=$Value"; return }
    }
    $insertAt = $range[1]
    while ($insertAt -gt $range[0] + 1 -and [string]::IsNullOrWhiteSpace($Lines[$insertAt - 1])) { $insertAt-- }
    $Lines.Insert($insertAt, "$Key=$Value")
}

function Copy-BrandingImages {
    if (-not (Test-Path -LiteralPath $script:ImageDir)) {
        New-Item -ItemType Directory -Path $script:ImageDir -Force | Out-Null
        Write-Log "Created $script:ImageDir"
    }
    foreach ($folder in 'Wallpaper', 'Lockscreen') {
        $source = Join-Path -Path $PSScriptRoot -ChildPath $folder
        if (Test-Path -LiteralPath $source) {
            Get-ChildItem -LiteralPath $source -File |
                Where-Object { $_.Extension -match '^\.(jpe?g|png|bmp|gif)$' } |
                Copy-Item -Destination $script:ImageDir -Force
        } else {
            Write-Log "Package folder .\$folder not found." 'WARN'
        }
    }

    $wallpaper = Join-Path -Path $script:ImageDir -ChildPath $WallpaperImg
    $lock      = Join-Path -Path $script:ImageDir -ChildPath $LockscreenImg
    if (-not (Test-Path -LiteralPath $wallpaper)) { Write-Log "Wallpaper '$WallpaperImg' not found after copy; wallpaper will be skipped." 'WARN'; $wallpaper = $null }
    if (-not (Test-Path -LiteralPath $lock))      { Write-Log "Lock screen '$LockscreenImg' not found after copy; lock screen will be skipped." 'WARN'; $lock = $null }
    Write-Log "Images copied to $script:ImageDir."
    return [pscustomobject]@{ Wallpaper = $wallpaper; LockScreen = $lock }
}

function Install-BrandingTheme {
    <#
        Copies the .theme into OEM Themes and makes that copy agree with this deployment, so applying the theme
        can't fight the accent color: AutoColorization=0 (no accent-from-wallpaper), the chosen ColorizationColor,
        SystemMode/AppMode, and the wallpaper path. Returns the deployed path and the resolved accent color.
    #>
    param([string]$WallpaperPath)

    $themeSourceDir = Join-Path -Path $PSScriptRoot -ChildPath 'Theme'
    $source = if ($ThemeFile) { Get-Item -LiteralPath (Join-Path $themeSourceDir $ThemeFile) -ErrorAction SilentlyContinue }
              else { Get-ChildItem -Path $themeSourceDir -Filter '*.theme' -File -ErrorAction SilentlyContinue | Select-Object -First 1 }

    if (-not (Test-Path -LiteralPath $script:ThemeDir)) { New-Item -ItemType Directory -Path $script:ThemeDir -Force | Out-Null }

    $themePath = $null
    $themeAccent = $null
    if ($source) {
        $themePath = Join-Path -Path $script:ThemeDir -ChildPath $source.Name
        Copy-Item -LiteralPath $source.FullName -Destination $themePath -Force

        $theme = Read-ThemeFile -Path $themePath
        $themeAccent = Get-ThemeValue -Lines $theme.Lines -Section 'VisualStyles' -Key 'ColorizationColor'
        $accent = if ($AccentColor) { $AccentColor } elseif ($themeAccent) { $themeAccent } else { $null }
        if (-not $accent) { throw 'No -AccentColor given and the .theme has no [VisualStyles] ColorizationColor.' }
        $hex = (Get-BrandingAccentData -Color $accent).Hex

        Set-ThemeValue -Lines $theme.Lines -Section 'VisualStyles' -Key 'AutoColorization'  -Value '0'
        Set-ThemeValue -Lines $theme.Lines -Section 'VisualStyles' -Key 'ColorizationColor' -Value "0XC4$hex"
        Set-ThemeValue -Lines $theme.Lines -Section 'VisualStyles' -Key 'SystemMode'        -Value $WindowsMode
        Set-ThemeValue -Lines $theme.Lines -Section 'VisualStyles' -Key 'AppMode'           -Value $AppMode
        if ($WallpaperPath) {
            $wallpaperValue = '%SystemRoot%' + $WallpaperPath.Substring($env:SystemRoot.Length)
            Set-ThemeValue -Lines $theme.Lines -Section 'Control Panel\Desktop' -Key 'Wallpaper' -Value $wallpaperValue
        }
        [IO.File]::WriteAllText($themePath, ($theme.Lines -join "`r`n"), $theme.Encoding)
        Write-Log "Theme deployed to $themePath (accent #$hex, $WindowsMode Windows mode, $AppMode app mode)."
    } else {
        Write-Log 'No .theme file found in the package; continuing with wallpaper, accent and lock screen only.' 'WARN'
        if (-not $AccentColor) { throw 'No .theme file and no -AccentColor given; cannot determine the accent color.' }
        $hex = (Get-BrandingAccentData -Color $AccentColor).Hex
    }

    return [pscustomobject]@{ ThemePath = $themePath; AccentColor = "#$hex" }
}

function Install-UserScript {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    if (-not (Test-Path -LiteralPath $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }

    # Users may read/execute but not modify - this script runs in every user's context
    $null = Invoke-NativeTool -FilePath "$env:SystemRoot\System32\icacls.exe" -Arguments @(
        "`"$script:AppDataDir`"", '/inheritance:r',
        '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX')

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Apply-UserBranding.ps1') -Destination $script:UserScript -Force
    $Config | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8 -Force
    Write-Log "User script and config written to $script:AppDataDir."
}

function Get-RunOnceCommand {
    return "`"$script:PsExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:UserScript`" -FirstLogon"
}

function Set-DefaultUserBranding {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)]$Accent)

    $mount    = 'BrandingDefaultUser'
    $hiveFile = Join-Path -Path $env:SystemDrive -ChildPath 'Users\Default\NTUSER.DAT'
    if (Test-Path -LiteralPath "Registry::HKEY_USERS\$mount") {
        $null = Invoke-NativeTool -FilePath 'reg.exe' -Arguments @('unload', "HKU\$mount")
    }
    $rc = Invoke-NativeTool -FilePath 'reg.exe' -Arguments @('load', "HKU\$mount", "`"$hiveFile`"")
    if ($rc -ne 0) { throw "reg load of $hiveFile failed (exit $rc)." }

    $root = $null
    try {
        $root = [Microsoft.Win32.Registry]::Users.OpenSubKey($mount, $true)
        Set-BrandingProfileValues -Root $root -Config $Config -Accent $Accent
        if ($Config.ThemePath) {
            Set-BrandingRegValue $root 'Software\Microsoft\Windows\CurrentVersion\Themes' 'CurrentTheme' $Config.ThemePath 'String'
        }
        if ($Config.WallpaperPath) {
            Set-BrandingRegValue $root 'Control Panel\Desktop' 'Wallpaper' $Config.WallpaperPath 'String'
        }
        # Every new profile applies the full branding once at first sign-in, as that user
        Set-BrandingRegValue $root 'Software\Microsoft\Windows\CurrentVersion\RunOnce' $script:RunOnceName (Get-RunOnceCommand) 'String'
        Write-Log 'Default User hive updated (accent, palette, color mode, wallpaper, theme, first-sign-in RunOnce).'
    } finally {
        if ($root) { $root.Close() }
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        $rc = 1
        for ($i = 0; $i -lt 5 -and $rc -ne 0; $i++) {
            $rc = Invoke-NativeTool -FilePath 'reg.exe' -Arguments @('unload', "HKU\$mount")
            if ($rc -ne 0) { Start-Sleep -Seconds 1 }
        }
        if ($rc -ne 0) { Write-Log "Could not unload HKU\$mount (exit $rc)." 'ERROR' }
    }
}

function Get-InteractiveUser {
    # Signed-in users = owners of explorer.exe (desktop running) or sihost.exe (signed in, desktop may not be up yet)
    $users = @{}
    $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe' OR Name='sihost.exe'"
    foreach ($p in $procs) {
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        $sid = $owner.Sid
        if (-not $sid -or $sid -notmatch '^S-1-(5-21|12-1)-') { continue }
        if (-not $users.ContainsKey($sid)) {
            $name = $sid
            try { $name = ([Security.Principal.SecurityIdentifier]$sid).Translate([Security.Principal.NTAccount]).Value } catch { }
            $users[$sid] = [pscustomobject]@{ Sid = $sid; Name = $name; HasDesktop = $false }
        }
        if ($p.Name -eq 'explorer.exe') { $users[$sid].HasDesktop = $true }
    }
    # defaultuser0 is the temporary Autopilot/OOBE account
    return @($users.Values | Where-Object { $_.Name -notmatch '\\defaultuser\d*$' })
}

function Invoke-UserBrandingTask {
    <#
        Runs Apply-UserBranding.ps1 once in the session of every signed-in user.
        The task principal is the built-in Users group, not a specific account. Task Scheduler running as SYSTEM
        can't always resolve Entra ID (AzureAD\) accounts or their SIDs ("No mapping between account names and
        security ids was done"), but a group principal needs no account lookup: Windows starts one instance in
        each signed-in member's session. -RequireDesktop makes the script exit in sessions with no desktop yet.
    #>
    param([Parameter(Mandatory)][object[]]$Users, [string]$ExtraArguments = '', [int]$TimeoutSeconds = 120)

    # Note where each user's log ends so only this run's lines are merged into the Intune log
    $userLogs = foreach ($u in $Users) {
        $profilePath = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($u.Sid)" -ErrorAction SilentlyContinue).ProfileImagePath
        $path = if ($profilePath) { Join-Path $profilePath 'AppData\Local\DesktopBranding\Apply-UserBranding.log' } else { $null }
        $skip = if ($path -and (Test-Path -LiteralPath $path)) { @(Get-Content -LiteralPath $path).Count } else { 0 }
        [pscustomobject]@{ User = $u; Path = $path; Skip = $skip }
    }

    $usersGroup = ([Security.Principal.SecurityIdentifier]'S-1-5-32-545').Translate([Security.Principal.NTAccount]).Value
    $taskName  = 'DesktopBranding-UserContext'
    $argument  = ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:UserScript`" -RequireDesktop $ExtraArguments").Trim()
    $action    = New-ScheduledTaskAction -Execute $script:PsExe -Argument $argument
    $principal = New-ScheduledTaskPrincipal -GroupId $usersGroup -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Write-Log "Running user-context script ($(if ($ExtraArguments) { $ExtraArguments } else { 'apply' })) for: $(($Users | ForEach-Object { $_.Name }) -join ', ')"
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $taskName
        $timer = [Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Seconds 3
        while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running' -and $timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            Start-Sleep -Seconds 2
        }
        $state = (Get-ScheduledTask -TaskName $taskName).State
        $info  = Get-ScheduledTaskInfo -TaskName $taskName
        if ($state -eq 'Running') { Write-Log "User task still running after $TimeoutSeconds s; leaving it to finish." 'WARN' }
        else { Write-Log "User task finished (LastTaskResult=$($info.LastTaskResult))." }
    } finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    foreach ($log in $userLogs) {
        if ($log.Path -and (Test-Path -LiteralPath $log.Path)) {
            Add-Content -Path $script:LogFile -Value "  --- $($log.User.Name) ---"
            Get-Content -LiteralPath $log.Path | Select-Object -Skip $log.Skip |
                ForEach-Object { Add-Content -Path $script:LogFile -Value "    $_" }
        } else {
            Write-Log "No user log found for $($log.User.Name) ($($log.Path))." 'WARN'
        }
    }
}

function Set-UserRunOnce {
    # Queues the per-user script to run when this user's desktop next starts
    param([Parameter(Mandatory)]$User)
    $hive = [Microsoft.Win32.Registry]::Users.OpenSubKey($User.Sid, $true)
    if (-not $hive) { Write-Log "Hive for $($User.Name) not loaded; cannot queue RunOnce." 'WARN'; return }
    try { Set-BrandingRegValue $hive 'Software\Microsoft\Windows\CurrentVersion\RunOnce' $script:RunOnceName (Get-RunOnceCommand) 'String' }
    finally { $hive.Close() }
}

function Invoke-SignedInUserBranding {
    $users = @(Get-InteractiveUser)
    if ($users.Count -eq 0) {
        Write-Log 'No signed-in users. Branding will apply at each new user''s first sign-in.'
        return
    }

    # Signed in but the desktop hasn't started (Autopilot account-setup ESP): their profile already exists, so the
    # Default User RunOnce won't reach them. Queue it in their own hive instead.
    foreach ($user in @($users | Where-Object { -not $_.HasDesktop })) {
        Set-UserRunOnce -User $user
        Write-Log "Desktop not started for $($user.Name); queued branding to run when it does (RunOnce)."
    }

    $desktopUsers = @($users | Where-Object { $_.HasDesktop })
    if ($desktopUsers.Count -eq 0) { return }
    try {
        Invoke-UserBrandingTask -Users $desktopUsers
    } catch {
        # Never fail the whole install over the live-session step: fall back to applying at their next sign-in
        Write-Log "Could not run the user-context task: $($_.Exception.Message). Queuing for next sign-in instead." 'WARN'
        foreach ($user in $desktopUsers) {
            try { Set-UserRunOnce -User $user } catch { Write-Log "RunOnce for $($user.Name) failed: $($_.Exception.Message)" 'WARN' }
        }
    }
}

# ==================== MAIN ====================
try {
    Write-Log "=== Install started (package version $Version) ==="
    Assert-Admin
    Remove-LegacyArtifacts

    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Apply-UserBranding.ps1'))) {
        throw 'Apply-UserBranding.ps1 is missing from the package.'
    }
    . (Join-Path $PSScriptRoot 'Apply-UserBranding.ps1')   # accent + registry helpers

    $images = Copy-BrandingImages
    $theme  = Install-BrandingTheme -WallpaperPath $images.Wallpaper

    $config = [ordered]@{
        Version           = $Version
        CompanyFolder     = $CompanyFolder
        ImageDir          = $script:ImageDir
        ThemePath         = $theme.ThemePath
        WallpaperPath     = $images.Wallpaper
        LockScreenPath    = $images.LockScreen
        AccentColor       = $theme.AccentColor
        WindowsMode       = $WindowsMode
        AppMode           = $AppMode
        AccentOnTitleBars = (-not $NoAccentOnTitleBars.IsPresent)
    }
    Install-UserScript -Config $config
    $configObj = [pscustomobject]$config
    $accent    = Get-BrandingAccentData -Color $config.AccentColor
    Write-Log ("Accent #{0}: AccentColorMenu=0x{1:X8} StartColorMenu=0x{2:X8} ColorizationColor=0x{3:X8}" -f `
        $accent.Hex, $accent.AccentColorMenu, $accent.StartColorMenu, $accent.ColorizationColor)

    Set-DefaultUserBranding -Config $configObj -Accent $accent
    try { Invoke-SignedInUserBranding }
    catch { Write-Log "Signed-in user step failed: $($_.Exception.Message). They'll get the branding from RunOnce or at next install." 'WARN' }

    $regPath = "HKLM:\SOFTWARE\$CompanyFolder\DesktopBranding"
    if (-not (Test-Path -LiteralPath $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    New-ItemProperty -Path $regPath -Name 'Version' -Value $Version -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $regPath -Name 'InstalledDate' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -PropertyType String -Force | Out-Null

    Write-Log '=== Install completed successfully ==='
    exit 0
} catch {
    Write-Log "Fatal error: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" 'ERROR'
    exit 1
}
