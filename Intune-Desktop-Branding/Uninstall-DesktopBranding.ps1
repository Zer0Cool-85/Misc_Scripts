<# Run the Company Portal uninstall as SYSTEM in native Windows PowerShell 5.1.
   Supply the same CompanyFolder used during install. Existing ThemeApply-1
   installations are supported using the original Theme, Wallpaper and Lockscreen
   source folders. An explicit ThemeName/WallpaperImg/LockscreenImg also works. #>
[CmdletBinding()]
param(
    [Alias('Location')][string]$CompanyFolder='Company',
    [string]$ThemeName,
    [string]$WallpaperImg,
    [string]$LockscreenImg,
    [switch]$UserReset,
    [int]$SessionId
)
$ErrorActionPreference='Stop'
function Write-Log([string]$Message) {
    $line = '{0:s} {1}' -f (Get-Date),$Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogFile -Value $line
}
function Assert-Leaf([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.','..') -or
        $Name -match '[\\/:*?"<>|\[\]]' -or $Name -match '[. ]$') { throw "Invalid file or folder name: $Name" }
}
function Get-ResetPlan {
    Assert-Leaf $CompanyFolder
    if (-not $ThemeName) {
        $themes = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Theme\*.theme') -File -ErrorAction SilentlyContinue)
        if ($themes.Count -ne 1) { throw 'Supply -ThemeName or keep the original single .theme in the package Theme folder.' }
        $ThemeName = $themes[0].Name
    }
    Assert-Leaf $ThemeName
    if ([IO.Path]::GetExtension($ThemeName) -ine '.theme') { throw 'ThemeName must name a .theme file.' }
    $images = @()
    foreach ($source in @('Wallpaper','Lockscreen')) {
        $explicit = if ($source -eq 'Wallpaper') { $WallpaperImg } else { $LockscreenImg }
        $names = if ($explicit) { $explicit } else {
            Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $source) -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.jpg','.jpeg','.png','.bmp','.gif' } |
                Select-Object -ExpandProperty Name
        }
        if (-not $names) { throw "Keep the original $source images in the package or specify the corresponding image filename." }
        foreach ($name in $names) {
            Assert-Leaf $name
            $images += Join-Path $imageDir $name
        }
    }
    [pscustomobject]@{ Theme=(Join-Path $themeDir $ThemeName); Images=@($images | Sort-Object -Unique) }
}
function Reset-User([object]$Plan) {
    if ($SessionId -le 0 -or (Get-Process -Id $PID).SessionId -ne $SessionId -or
        [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in 'S-1-5-18','S-1-5-19','S-1-5-20') { throw 'Wrong desktop session for reset.' }
    $current=[Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes' -ErrorAction SilentlyContinue).CurrentTheme)
    $paper=[Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).Wallpaper)
    $ownedPaper=$paper -in $Plan.Images
    $ownedTheme=$current -ieq $Plan.Theme
    Write-Log "Matched deployed theme=$ownedTheme, wallpaper=$ownedPaper."
    $stock=Join-Path $env:SystemRoot 'Resources\Themes\aero.theme'
    $stockPaper=Join-Path $env:SystemRoot 'Web\Wallpaper\Windows\img0.jpg'
    if ($ownedTheme -and $ownedPaper) {
        if (-not (Test-Path -LiteralPath $stock -PathType Leaf)) { throw "Stock theme unavailable: $stock" }
        Start-Process -FilePath $stock
        Start-Sleep -Seconds 3
    }
    if ($ownedPaper) {
        if (-not (Test-Path -LiteralPath $stockPaper -PathType Leaf)) { throw "Stock wallpaper unavailable: $stockPaper" }
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class DesktopBrandingReset {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SystemParametersInfoW(uint action, uint param, string path, uint flags);
}
'@
        if (-not [DesktopBrandingReset]::SystemParametersInfoW(20,0,$stockPaper,3)) { throw 'Windows could not reset the wallpaper.' }
    }
    # OriginalImageFile may be a cache URI or unavailable for Spotlight/stream images.
    $lockUri=$null
    try { $lockUri=[Windows.System.UserProfile.LockScreen,Windows.System.UserProfile,ContentType=WindowsRuntime]::OriginalImageFile }
    catch { Write-Log "Current lock image could not be identified: $($_.Exception.Message)" }
    $ownedLock=$false
    if ($lockUri -and $lockUri.IsFile) {
        $ownedLock=$lockUri.LocalPath -in $Plan.Images
        if (-not $ownedLock) {
            try {
                if (Test-Path -LiteralPath $lockUri.LocalPath -PathType Leaf) {
                    $currentHash=(Get-FileHash -LiteralPath $lockUri.LocalPath).Hash
                    foreach ($image in $Plan.Images) {
                        if ((Test-Path -LiteralPath $image -PathType Leaf) -and
                            (Get-FileHash -LiteralPath $image).Hash -eq $currentHash) { $ownedLock=$true; break }
                    }
                }
            } catch { Write-Log "Cannot compare cached lock image: $($_.Exception.Message)" }
        }
    }
    if ($ownedLock) {
        $stockLock=Join-Path $env:SystemRoot 'Web\Screen\img100.jpg'
        if (-not (Test-Path -LiteralPath $stockLock -PathType Leaf)) { throw "Stock lock image unavailable: $stockLock" }
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $methods=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
        $getFile=@($methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -ceq 'IAsyncOperation`1' })[0]
        $action=@($methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -ceq 'IAsyncAction' })[0]
        $type=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
        $read=$getFile.MakeGenericMethod($type).Invoke($null,@($type::GetFileFromPathAsync($stockLock)))
        $read.Wait()
        $set=$action.Invoke($null,@([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($read.Result)))
        $set.Wait()
        Write-Log 'Reset the identified corporate lock image.'
    } else { Write-Log 'Kept the current lock image because its source did not match a deployed file.' }
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

function Invoke-UserResetTask([int]$Target,[object]$Plan) {
    # Windows Program Files grants standard users read/execute in newly created folders.
    $work=Join-Path $env:ProgramFiles ('DesktopBranding\Reset-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $worker=Join-Path $work 'Reset.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $worker
    $Plan | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'Plan.json') -Encoding UTF8
    $name='RevertOrgThemeTemp'
    $localUsers=([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')).Translate([Security.Principal.NTAccount]).Value
    $principal=New-ScheduledTaskPrincipal -GroupId $localUsers -RunLevel Limited
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argsText='-NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -UserReset -SessionId {1}' -f $worker,$Target
    $action=New-ScheduledTaskAction -Execute $exe -Argument $argsText
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
    Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    $requested=(Get-Date).AddSeconds(-1)
    Start-DesktopBrandingTask -TaskName $name -SessionId $Target
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 1
        $info=Get-ScheduledTaskInfo -TaskName $name
        $state=(Get-ScheduledTask -TaskName $name).State
        $done=$info.LastRunTime -ge $requested -and $state -notin 'Running','Queued'
    } until ($done -or $timer.Elapsed.TotalSeconds -ge 180)
    if (-not $done -or $info.LastTaskResult -ne 0) {
        throw "Reset task finished=$done result=$($info.LastTaskResult), session=$Target. See the user's %LOCALAPPDATA%\DesktopBranding\Uninstall.log. Helper: $worker"
    }
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    Remove-Item -LiteralPath $work -Recurse -Force
}
try {
    if ($UserReset) {
        $dir=Join-Path $env:LOCALAPPDATA 'DesktopBranding'
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        $script:LogFile=Join-Path $dir 'Uninstall.log'
        Reset-User (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'Plan.json') | ConvertFrom-Json)
        Write-Log 'Completed current-user reset.'
        exit 0
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Run the uninstaller in native Windows PowerShell (Sysnative from a 32-bit host).' }
    $script:LogFile=Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\App-Uninstall-DesktopBranding.log'
    New-Item -Path (Split-Path $script:LogFile) -ItemType Directory -Force | Out-Null
    $key='HKLM:\SOFTWARE\Company\DesktopBranding'
    Assert-Leaf $CompanyFolder
    $imageDir=Join-Path $env:SystemRoot "Web\Wallpaper\$CompanyFolder"
    $themeDir=Join-Path $env:SystemRoot 'Resources\OEM Themes'
    $plan=Get-ResetPlan
    # Recover the installed image folder from the deployed ThemeApply-1 copy on older deployments.
    if (Test-Path -LiteralPath $plan.Theme -PathType Leaf) {
        $themeText=Get-Content -LiteralPath $plan.Theme -Raw
        $wallpaper=Get-DesktopBrandingThemeValue $themeText 'Control Panel\Desktop' Wallpaper
        if ($wallpaper) {
            $wallpaper=[Environment]::ExpandEnvironmentVariables($wallpaper)
            if ([IO.Path]::IsPathRooted($wallpaper)) {
                $stagedDir=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($wallpaper))
                $wallRoot=Join-Path $env:SystemRoot 'Web\Wallpaper'
                if ([IO.Path]::GetDirectoryName($stagedDir) -ieq $wallRoot -and $stagedDir -ine $imageDir) {
                    if ($PSBoundParameters.ContainsKey('CompanyFolder')) { throw "Installed theme references $stagedDir but parameters select $imageDir." }
                    $CompanyFolder=[IO.Path]::GetFileName($stagedDir)
                    Assert-Leaf $CompanyFolder
                    $imageDir=$stagedDir
                    $plan=Get-ResetPlan
                }
            }
        }
    }
    Write-Log "Uninstalling $($plan.Theme), images: $($plan.Images -join ', ')"
    $target=Get-DesktopBrandingSession
    if ($target -gt 0) { Invoke-UserResetTask $target $plan }
    else { Write-Log 'No Explorer session. Cleaning device files and profile defaults.' }
    Invoke-DefaultProfileEdit {
        param($root)
        $themes=$root.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes',$true)
        if ($themes) {
            try {
                if ([Environment]::ExpandEnvironmentVariables([string]$themes.GetValue('CurrentTheme')) -ieq $plan.Theme) {
                    $themes.SetValue('CurrentTheme',(Join-Path $env:SystemRoot 'Resources\Themes\aero.theme'))
                }
            } finally { $themes.Close() }
        }
    }
    foreach ($file in @($plan.Theme) + @($plan.Images)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
    }
    if ((Test-Path -LiteralPath $imageDir) -and @(Get-ChildItem -LiteralPath $imageDir -Force).Count -eq 0) {
        Remove-Item -LiteralPath $imageDir
    }
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    Write-Log 'Uninstall completed. Company Portal detection marker removed.'
    exit 0
} catch {
    $detail="Uninstall failed at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    if ($script:LogFile) { try { Write-Log $detail } catch {} }
    [Console]::Error.WriteLine($detail)
    exit 1
}
