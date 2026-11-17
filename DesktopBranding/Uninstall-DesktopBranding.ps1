<#
.SYNOPSIS
    Removes the corporate branding package and reverts users to stock Windows only where they haven't
    already personalised things themselves.

.DESCRIPTION
    Runs as SYSTEM from the Intune Win32 app uninstall command.

    Execution workflow:
    1. Relaunches itself in 64-bit PowerShell.
    2. Signed-in users with a running desktop: runs Apply-UserBranding.ps1 -Revert in their context. Each element
       (theme, accent, wallpaper, lock screen) is reset only if it still matches what the package applied.
    3. Removes the pending first-sign-in RunOnce entry from loaded user hives.
    4. Default User hive: removes the seeded accent/color values and RunOnce, resets theme to aero.theme and
       wallpaper to img0.jpg.
    5. Deletes the deployed .theme (other OEM themes are left alone), the image folder, %ProgramData%\DesktopBranding,
       and the Intune detection key.

.PARAMETER CompanyFolder
    Must match the install. Aliased as -Location. Defaults to "Company".

.PARAMETER ThemeName
    .theme file name to delete from C:\Windows\Resources\OEM Themes\. Normally read from branding.json; falls back to
    this parameter, then to the file name(s) in the package's .\Theme\ folder.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1

.NOTES
    Log: %ProgramData%\Microsoft\IntuneManagementExtension\Logs\Uninstall-DesktopBranding.log
#>
[CmdletBinding()]
param(
    [Alias('Location')]
    [string]$CompanyFolder = 'Company',
    [string]$ThemeName
)

# === Relaunch in 64-bit PowerShell ===
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path -Path $env:SystemRoot -ChildPath 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $relaunchArgs = @()
    foreach ($kv in $PSBoundParameters.GetEnumerator()) { $relaunchArgs += "-$($kv.Key)"; $relaunchArgs += [string]$kv.Value }
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
$script:DefaultTheme = Join-Path -Path $env:SystemRoot -ChildPath 'Resources\Themes\aero.theme'
$script:DefaultWall  = Join-Path -Path $env:SystemRoot -ChildPath 'Web\Wallpaper\Windows\img0.jpg'
$script:LogFile      = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft\IntuneManagementExtension\Logs\Uninstall-DesktopBranding.log'

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
}

function Invoke-NativeTool {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

function Get-BrandingConfig {
    # Prefer what the install recorded; rebuild a minimal config if it's missing (e.g. a partial install)
    if (Test-Path -LiteralPath $script:ConfigFile) {
        try { return Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json } catch {
            Write-Log "Could not read $script:ConfigFile; rebuilding config." 'WARN'
        }
    }
    $theme = if ($ThemeName) { $ThemeName }
             else { Get-ChildItem -Path (Join-Path $PSScriptRoot 'Theme') -Filter '*.theme' -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name }
    return [pscustomobject]@{
        Version        = 0
        CompanyFolder  = $CompanyFolder
        ImageDir       = $script:ImageDir
        ThemePath      = $(if ($theme) { Join-Path $script:ThemeDir $theme } else { $null })
        WallpaperPath  = $null
        LockScreenPath = $null
    }
}

function Initialize-UserScript {
    # The revert runs as each user, so the user script and config must be present (and read-only to users)
    param([Parameter(Mandatory)]$Config)
    if (-not (Test-Path -LiteralPath $script:AppDataDir)) {
        New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
        $null = Invoke-NativeTool -FilePath "$env:SystemRoot\System32\icacls.exe" -Arguments @(
            "`"$script:AppDataDir`"", '/inheritance:r',
            '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX')
    }
    $packaged = Join-Path $PSScriptRoot 'Apply-UserBranding.ps1'
    if (Test-Path -LiteralPath $packaged) { Copy-Item -LiteralPath $packaged -Destination $script:UserScript -Force }
    if (-not (Test-Path -LiteralPath $script:UserScript)) { throw 'Apply-UserBranding.ps1 not found in the package or ProgramData.' }
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
        $Config | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8 -Force
    }
}

function Get-InteractiveUser {
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
    return @($users.Values | Where-Object { $_.Name -notmatch '\\defaultuser\d*$' })
}

function Invoke-UserBrandingTask {
    param([Parameter(Mandatory)]$User, [string]$ExtraArguments = '', [int]$TimeoutSeconds = 120)

    $profilePath = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($User.Sid)" -ErrorAction SilentlyContinue).ProfileImagePath
    $userLog = if ($profilePath) { Join-Path $profilePath 'AppData\Local\DesktopBranding\Apply-UserBranding.log' }
    $linesBefore = if ($userLog -and (Test-Path -LiteralPath $userLog)) { @(Get-Content -LiteralPath $userLog).Count } else { 0 }

    $taskName = "DesktopBranding-$($User.Sid)"
    $argument = ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:UserScript`" $ExtraArguments").Trim()
    $action    = New-ScheduledTaskAction -Execute $script:PsExe -Argument $argument
    $principal = New-ScheduledTaskPrincipal -UserId $User.Sid -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Write-Log "Running user-context revert for $($User.Name) ($($User.Sid))..."
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $taskName
        $timer = [Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Seconds 3
        while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running' -and $timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            Start-Sleep -Seconds 2
        }
        $info = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Log "User task for $($User.Name) state=$((Get-ScheduledTask -TaskName $taskName).State) LastTaskResult=$($info.LastTaskResult)."
    } finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    if ($userLog -and (Test-Path -LiteralPath $userLog)) {
        Get-Content -LiteralPath $userLog | Select-Object -Skip $linesBefore | ForEach-Object { Add-Content -Path $script:LogFile -Value "    $_" }
    }
}

function Reset-SignedInUsers {
    $users = Get-InteractiveUser
    if (-not $users) { Write-Log 'No signed-in users; user revert skipped.'; return }
    foreach ($user in $users) {
        if ($user.HasDesktop) { Invoke-UserBrandingTask -User $user -ExtraArguments '-Revert' }
        else { Write-Log "Desktop not started for $($user.Name); skipping user revert." }
    }
}

function Remove-PendingRunOnce {
    # Cancels first-sign-in branding that was queued but hasn't run yet, for any user hive currently loaded
    foreach ($sid in [Microsoft.Win32.Registry]::Users.GetSubKeyNames()) {
        if ($sid -notmatch '^S-1-(5-21|12-1)-[\d-]+$') { continue }
        $hive = [Microsoft.Win32.Registry]::Users.OpenSubKey($sid, $true)
        if (-not $hive) { continue }
        try { Remove-BrandingRegValue $hive 'Software\Microsoft\Windows\CurrentVersion\RunOnce' $script:RunOnceName }
        finally { $hive.Close() }
    }
}

function Reset-DefaultUserBranding {
    $mount    = 'BrandingDefaultUser'
    $hiveFile = Join-Path -Path $env:SystemDrive -ChildPath 'Users\Default\NTUSER.DAT'
    if (Test-Path -LiteralPath "Registry::HKEY_USERS\$mount") {
        $null = Invoke-NativeTool -FilePath 'reg.exe' -Arguments @('unload', "HKU\$mount")
    }
    $rc = Invoke-NativeTool -FilePath 'reg.exe' -Arguments @('load', "HKU\$mount", "`"$hiveFile`"")
    if ($rc -ne 0) { Write-Log "reg load of $hiveFile failed (exit $rc); Default User hive not reset." 'ERROR'; return }

    $root = $null
    try {
        $root = [Microsoft.Win32.Registry]::Users.OpenSubKey($mount, $true)
        Remove-BrandingRegValue $root 'Software\Microsoft\Windows\CurrentVersion\RunOnce' $script:RunOnceName
        Remove-BrandingRegValue $root 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' @('AccentPalette', 'AccentColorMenu', 'StartColorMenu')
        Remove-BrandingRegValue $root 'Software\Microsoft\Windows\DWM' @('AccentColor', 'ColorizationColor', 'ColorizationAfterglow', 'ColorPrevalence', 'EnableWindowColorization')
        Remove-BrandingRegValue $root 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' @('SystemUsesLightTheme', 'AppsUseLightTheme', 'ColorPrevalence')
        Remove-BrandingRegValue $root 'Control Panel\Desktop' 'AutoColorization'
        Set-BrandingRegValue $root 'Software\Microsoft\Windows\CurrentVersion\Themes' 'CurrentTheme' $script:DefaultTheme 'String'
        if (Test-Path -LiteralPath $script:DefaultWall) {
            Set-BrandingRegValue $root 'Control Panel\Desktop' 'Wallpaper' $script:DefaultWall 'String'
        }
        Write-Log 'Default User hive reset to stock values.'
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

function Remove-BrandingFiles {
    param([Parameter(Mandatory)]$Config)

    # Only the theme(s) this package deployed - other OEM themes are left alone
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if ($Config.ThemePath) { [void]$names.Add((Split-Path -Path $Config.ThemePath -Leaf)) }
    if ($ThemeName)        { [void]$names.Add($ThemeName) }
    Get-ChildItem -Path (Join-Path $PSScriptRoot 'Theme') -Filter '*.theme' -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$names.Add($_.Name) }

    if (Test-Path -LiteralPath $script:ThemeDir) {
        foreach ($name in $names) {
            $target = Join-Path -Path $script:ThemeDir -ChildPath $name
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                Write-Log "Removed theme file: $target"
            }
        }
        Remove-Item -LiteralPath (Join-Path $script:ThemeDir 'Apply-UserTheme.ps1') -Force -ErrorAction SilentlyContinue  # legacy helper
        if (-not (Get-ChildItem -LiteralPath $script:ThemeDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $script:ThemeDir -Force -ErrorAction SilentlyContinue
            Write-Log "Removed empty directory: $script:ThemeDir"
        }
    }

    foreach ($dir in @($script:ImageDir, $script:AppDataDir)) {
        if (Test-Path -LiteralPath $dir) {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed directory: $dir"
        }
    }
}

# ==================== MAIN ====================
try {
    Write-Log '=== Uninstall started ==='
    Assert-Admin
    foreach ($task in 'ApplyOrgThemeTemp', 'RevertOrgThemeTemp') {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue   # legacy tasks
    }

    $config = Get-BrandingConfig
    Initialize-UserScript -Config $config
    . $script:UserScript   # registry helpers

    Reset-SignedInUsers
    Remove-PendingRunOnce
    Reset-DefaultUserBranding
    Remove-BrandingFiles -Config $config

    $regPath = "HKLM:\SOFTWARE\$CompanyFolder\DesktopBranding"
    Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction SilentlyContinue
    $parent = "HKLM:\SOFTWARE\$CompanyFolder"
    if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent) -and
        -not (Get-Item -LiteralPath $parent).Property) {
        Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
    }

    Write-Log '=== Uninstall completed successfully ==='
    exit 0
} catch {
    Write-Log "Fatal error: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" 'ERROR'
    exit 1
}
