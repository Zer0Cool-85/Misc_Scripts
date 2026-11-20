<#
.SYNOPSIS
    Removes deployed corporate branding assets and reverts the Windows theme and lock screen to stock defaults.

.DESCRIPTION
    Designed to run in the SYSTEM context via an Intune Win32 app uninstall command.
    Safely cleans up the corporate theme, wallpaper, and lock screen without disturbing pre-existing OEM themes
    or overwriting personalization choices if the end user has already customized their own theme.

    Execution workflow:
    1. Identifies the deployed .theme file(s) and removes them from C:\Windows\Resources\OEM Themes\
       (removing the folder only if empty so manufacturer OEM themes are preserved).
    2. Removes the C:\Windows\Web\Wallpaper\<CompanyFolder>\ directory and all branding images inside it.
    3. Mounts C:\Users\Default\NTUSER.DAT and resets CurrentTheme to the stock Windows theme (aero.theme).
    4. Detects if a user is currently signed into an active desktop session; if their active theme is still
       the removed corporate theme, reverts them to stock aero.theme and resets the lock screen to img100.jpg.

.PARAMETER CompanyFolder
    Optional. The subfolder name inside C:\Windows\Web\Wallpaper\ to remove.
    Aliased as -Location. Defaults to "Company".

.PARAMETER ThemeName
    Optional. Specific .theme filename to delete from C:\Windows\Resources\OEM Themes\ (e.g., "Custom.theme").
    If omitted, the script automatically checks the package's .\Theme\ subfolder to match the deployed filename(s).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1

    Removes C:\Windows\Web\Wallpaper\Company\, deletes the deployed .theme file from OEM Themes, resets
    the default user hive, and reverts the active user if they are still using the corporate theme.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1 -CompanyFolder "Company" -ThemeName "Autopilot.theme"

    Explicitly targets Autopilot.theme for removal without relying on the package's .\Theme\ subfolder.

.NOTES
    Intune Win32 App Deployment Settings:
    - Uninstall command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1

    Log File Location:
    %ProgramData%\Microsoft\IntuneManagementExtension\Logs\App-Uninstall-DesktopBranding.log
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Alias("Location")]
    [string]$CompanyFolder = "Company",
    [string]$ThemeName
)

# === GLOBAL VARIABLES ===
$script:ThemeDir       = Join-Path -Path $env:SystemRoot -ChildPath "Resources\OEM Themes"
$script:ImageDir       = Join-Path -Path $env:SystemRoot -ChildPath "Web\Wallpaper\$CompanyFolder"
$script:DefaultTheme   = Join-Path -Path $env:SystemRoot -ChildPath "Resources\Themes\aero.theme"
$script:DefaultLockImg = Join-Path -Path $env:SystemRoot -ChildPath "Web\Screen\img100.jpg"
$script:LogFile        = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\App-Uninstall-DesktopBranding.log"

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

function Remove-BrandingMaterial {
    Write-Log "Starting removal of branding files..."

    # 1. Remove deployed .theme file(s) safely
    if (Test-Path $script:ThemeDir) {
        $themesToRemove = @()

        if ($ThemeName) {
            $themesToRemove += $ThemeName
        } elseif (Test-Path ".\Theme\*.theme") {
            $themesToRemove += (Get-ChildItem -Path ".\Theme\*.theme").Name
        }

        if ($themesToRemove.Count -gt 0) {
            foreach ($tName in $themesToRemove) {
                $targetTheme = Join-Path -Path $script:ThemeDir -ChildPath $tName
                if (Test-Path $targetTheme) {
                    Remove-Item -Path $targetTheme -Force -ErrorAction SilentlyContinue
                    Write-Log "Removed theme file: $targetTheme"
                }
            }
        } else {
            Write-Log "No specific .theme filename matched; skipping theme file deletion to protect OEM themes." "WARN"
        }

        # Clean up any leftover helper script if an install was previously interrupted
        $leftoverHelper = Join-Path -Path $script:ThemeDir -ChildPath "Apply-UserTheme.ps1"
        if (Test-Path $leftoverHelper) {
            Remove-Item -Path $leftoverHelper -Force -ErrorAction SilentlyContinue
        }

        # Remove OEM Themes folder only if it is completely empty
        if ((Get-ChildItem -Path $script:ThemeDir -Force | Measure-Object).Count -eq 0) {
            Remove-Item -Path $script:ThemeDir -Force -ErrorAction SilentlyContinue
            Write-Log "Removed empty directory: $script:ThemeDir"
        }
    }

    # 2. Remove wallpaper/lockscreen folder
    if (Test-Path $script:ImageDir) {
        Remove-Item -Path $script:ImageDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed image directory: $script:ImageDir"
    } else {
        Write-Log "Image directory not found (already removed): $script:ImageDir"
    }
}

function Reset-FutureUserTheme {
    Write-Log "Resetting default theme for future user profiles to aero.theme..."
    try {
        reg load HKU\DefaultUser "C:\Users\Default\NTUSER.DAT" | Out-Null
        reg add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes" /v "CurrentTheme" /t REG_SZ /d "$script:DefaultTheme" /f | Out-Null
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        reg unload HKU\DefaultUser | Out-Null
        Write-Log "DefaultUser registry hive reset successfully."
    } catch {
        Write-Log "Failed to reset DefaultUser registry: $($_.Exception.Message)" "ERROR"
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

function Reset-ActiveUserTheme {
    $TargetSessionId = Get-DesktopBrandingSession
    if ($TargetSessionId -eq 0) {
        Write-Log "No Explorer desktop is present. Current-user step skipped."
        return
    }
    Write-Log "Preparing current-user helper for desktop session $TargetSessionId."
    $tempUserScript = Join-Path -Path $env:Temp -ChildPath "Revert-UserTheme.ps1"

    $UserScriptContent = @"
`$ErrorActionPreference = 'Stop'
try {
if ((Get-Process -Id `$PID).SessionId -ne $TargetSessionId -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    throw 'Reset helper did not start in the requested interactive user session.'
}
`$DefaultTheme   = '$script:DefaultTheme'
`$DefaultLockImg = '$script:DefaultLockImg'
`$RemovedThemeDir = '$script:ThemeDir'

`$currentTheme = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -Name 'CurrentTheme' -ErrorAction SilentlyContinue).CurrentTheme

# Only revert if the user is still using the removed corporate theme (preserve user customizations)
if (`$currentTheme -and (`$currentTheme -like "`$RemovedThemeDir*" -or -not (Test-Path `$currentTheme))) {
    if (Test-Path `$DefaultTheme) {
        Start-Process -FilePath `$DefaultTheme
        Start-Sleep -Seconds 3
        Stop-Process -Name 'SystemSettings' -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path `$DefaultLockImg) {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        `$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { `$_.Name -eq 'AsTask' -and `$_.GetParameters().Count -eq 1 -and `$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation``1' })[0]

        function Await(`$WinRtTask, `$ResultType) {
            `$asTask = `$asTaskGeneric.MakeGenericMethod(`$ResultType)
            `$netTask = `$asTask.Invoke(`$null, @(`$WinRtTask))
            `$netTask.Wait(-1) | Out-Null
            return `$netTask.Result
        }
        function AwaitAction(`$WinRtAction) {
            `$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { `$_.Name -eq 'AsTask' -and `$_.GetParameters().Count -eq 1 -and -not `$_.IsGenericMethod })[0]
            `$netTask = `$asTask.Invoke(`$null, @(`$WinRtAction))
            `$netTask.Wait(-1) | Out-Null
        }

        [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
        [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null

        `$ImageFile = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync(`$DefaultLockImg)) ([Windows.Storage.StorageFile])
        AwaitAction ([Windows.System.UserProfile.LockScreen]::SetImageFileAsync(`$ImageFile))
    }
}
} catch {
    [Console]::Error.WriteLine(`$_.Exception.ToString())
    exit 1
}
exit 0
"@
    $UserScriptContent | Set-Content -Path $tempUserScript -Encoding UTF8 -Force

    # Clean up any stale install task if present
    Unregister-ScheduledTask -TaskName "ApplyOrgThemeTemp" -Confirm:$false -ErrorAction SilentlyContinue

    $TaskName = "RevertOrgThemeTemp"
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
        throw "User task failed with result $($taskInfo.LastTaskResult). Task/helper retained; helper: $tempUserScript"
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Path $tempUserScript -Force -ErrorAction SilentlyContinue
    Write-Log "Active user check and cleanup completed."
}

# ==================== MAIN ====================
try {
    Write-Log "=== Uninstall script started ==="
    Assert-Admin
    Remove-BrandingMaterial
    Reset-FutureUserTheme
    Reset-ActiveUserTheme
    # Remove Intune detection registry key
    Remove-Item -Path "HKLM:\SOFTWARE\Company\DesktopBranding" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "=== Uninstall script completed successfully ==="
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    exit 1
}