# Shared helpers for the supplied step worker, Windows PowerShell 5.1 x64.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $env:SETUP_RUN_DIRECTORY -or -not $env:SETUP_PACKAGE_ROOT) {
    throw 'Run this script through the Setup UI worker; see Docs/ENTERPRISE-STEPS.md.'
}
if (-not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell is required.' }

function Write-EnterpriseLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','MSI')][string]$Level = 'INFO')
    $line = '{0} [{1}] [{2}] {3}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'), $env:SETUP_STEP_ID, $Level, $Message
    Add-SetupLogLine -Path (Join-Path $env:SETUP_RUN_DIRECTORY 'SetupUI.log') -Line $line
    if ($Level -ne 'MSI') { Write-Host $line }
}

function Set-EnterpriseProgress {
    param([string]$Message)
    Write-EnterpriseLog $Message
    Write-SetupProgress -Message $Message
}

function Resolve-EnterpriseFile {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Resolve-SetupContentPath -Root $env:SETUP_PACKAGE_ROOT -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Stage the required payload first: $RelativePath" }
    return $path
}

function Assert-MicrosoftBinary {
    param([string]$Path)
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Expected a valid Microsoft Authenticode signature: $Path"
    }
}

function Get-EnterpriseUserSid {
    param([string]$TargetUserSid = '')
    $session = (Get-Process -Id $PID).SessionId
    if ($session -eq 0 -and -not $TargetUserSid) { throw 'No interactive session. Use ServiceUI or supply the logged-on TargetUserSid.' }
    $owners = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object {
        if ($TargetUserSid -or $_.SessionId -eq $session) {
            $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid
            if ($owner.ReturnValue -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$owner.Sid) -and $owner.Sid -notin @('S-1-5-18','S-1-5-19','S-1-5-20')) { $owner.Sid }
        }
    } | Sort-Object -Unique)
    if ($TargetUserSid) {
        if ($TargetUserSid -notin $owners) { throw 'The specified TargetUserSid has no interactive Explorer session.' }
        Write-EnterpriseLog "Using explicit interactive user SID $TargetUserSid; setup session $session."
        return $TargetUserSid
    }
    if ($owners.Count -ne 1) { throw 'Cannot identify one interactive user in the setup session.' }
    Write-EnterpriseLog "Resolved Explorer owner SID $($owners[0]); setup session $session."
    return [string]$owners[0]
}

function Test-EnterpriseUserApp {
    param([string]$Name, [string]$UserSid)
    # Validate syntax without translating a cloud SID to an account name.
    try { $targetSid = [Security.Principal.SecurityIdentifier]::new($UserSid).Value }
    catch { throw "Invalid interactive user SID '$UserSid'. Check the Explorer-owner entry in SetupUI.log. $($_.Exception.Message)" }
    if ($targetSid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { throw 'App detection requires the interactive user SID, not a service-account SID.' }
    # Avoid Get-AppxPackage -User's SID/account resolution path. AllUsers still
    # requires admin/SYSTEM; match the exact target's Installed registration.
    try { $packages = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop) }
    catch { throw "AppX inventory query failed for '$Name', target SID '$targetSid'. No missing-app conclusion was recorded. $($_.Exception.Message)" }
    foreach ($package in $packages) {
        if ($package.Name -ne $Name -or $package.Status -ne 'Ok' -or $package.IsPartiallyStaged -or
            $package.Publisher -notmatch 'O=Microsoft Corporation(?:,|$)') { continue }
        if ($null -eq $package.PSObject.Properties['PackageUserInformation']) {
            throw "AppX returned no PackageUserInformation property for '$Name'; user installation could not be verified."
        }
        foreach ($user in @($package.PackageUserInformation)) {
            if ($null -ne $user -and [string]$user.UserSecurityId -eq $targetSid -and [string]$user.InstallState -eq 'Installed') { return $true }
        }
    }
    # Another user's registration, or Staged for this user, is not installed.
    return $false
}

function Set-CompanyPortalState {
    param([string]$RegistryPath, [string]$UserSid, [bool]$Present)
    if ($RegistryPath -notmatch '^HKLM:\\SOFTWARE\\[A-Za-z0-9 ._\\-]+$') { throw 'RegistryPath must be under HKLM:\SOFTWARE.' }
    New-Item -Path $RegistryPath -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'NeedsCompanyPortal' -PropertyType DWord -Value ([int](-not $Present)) -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'TargetUserSid' -PropertyType String -Value $UserSid -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'CheckedUtc' -PropertyType String -Value ([DateTime]::UtcNow.ToString('o')) -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'DetectionScope' -PropertyType String -Value 'InteractiveUserRegistration' -Force | Out-Null
}

function Invoke-EnterpriseUserAction {
    param([string]$UserSid, [hashtable]$Request, [ValidateRange(30,1800)][int]$TimeoutSeconds = 300)
    # A short-lived, unelevated interactive task. No passwords or user-writable
    # completion files are used. The SYSTEM caller independently verifies state.
    $scriptPath = Join-Path $PSScriptRoot 'Invoke-UserAction.ps1'
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Depth 8 -Compress)))
    $code = "& '" + $scriptPath.Replace("'", "''") + "' -RequestBase64 '$payload'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $taskName = 'PostEnrollment-UserAction-' + [Guid]::NewGuid().ToString('N')
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $principal = New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromSeconds($TimeoutSeconds)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $startRequested = $false
    $finished = $false
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        $before = (Get-ScheduledTaskInfo -TaskName $taskName).LastRunTime
        $startRequested = $true
        Start-ScheduledTask -TaskName $taskName
        $watch = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Seconds 1
            $info = Get-ScheduledTaskInfo -TaskName $taskName
            $state = (Get-ScheduledTask -TaskName $taskName).State
            if ($info.LastRunTime -gt $before -and $state -notin @('Running','Queued')) {
                $finished = $true
                if ($Request.Action -eq 'InstallStoreWithWinGet') {
                    $taskResult = [long]$info.LastTaskResult
                    Write-EnterpriseLog ("WinGet user task finished: exit {0} (0x{0:X8}); attempt {1}." -f $taskResult, $Request.AttemptId)
                    if ($taskResult -in @(12001, 3221225786, 267014)) {
                        $unsafeFailure = [InvalidOperationException]::new('WinGet cancellation could not be confirmed. Review the user WinGet logs before retrying; offline fallback was not started.')
                        $unsafeFailure.Data['DoNotFallback'] = $true
                        throw $unsafeFailure
                    }
                    if ($taskResult -ne 0) { throw ("WinGet user task exited with code {0} (0x{0:X8}); see the user log folder for attempt {1}." -f $taskResult, $Request.AttemptId) }
                }
                if ($info.LastTaskResult -ne 0) { throw "User action failed (task result $($info.LastTaskResult)). See the user's TEMP\PostEnrollment-UserAction.log and AppXDeploymentServer event log." }
                return
            }
        } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
        if ($Request.Action -eq 'InstallStoreWithWinGet') {
            $unsafeFailure = [TimeoutException]::new('The WinGet user task did not finish within its outer timeout. Offline fallback was not started because installer termination could not be confirmed.')
            $unsafeFailure.Data['DoNotFallback'] = $true
            throw $unsafeFailure
        }
        throw 'Timed out waiting for the interactive user action.'
    }
    catch {
        if ($Request.Action -eq 'InstallStoreWithWinGet' -and $startRequested -and -not $finished) {
            $_.Exception.Data['DoNotFallback'] = $true
            Write-EnterpriseLog -Level ERROR -Message 'WinGet task completion could not be confirmed. Offline fallback was not started; review the task/user logs before retrying.'
        }
        throw
    }
    finally {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

function Install-EnterpriseStoreApp {
    param([string]$Name, [string]$UserSid, [string]$PackageRelativePath,
        [string[]]$DependencyRelativePaths = @(), [string]$LicenseRelativePath = '',
        [bool]$AllowUnlicensedPackage = $false)
    if (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid) { Set-EnterpriseProgress "$Name is already available."; return }
    if (-not $PackageRelativePath) { throw "Stage the official $Name package, dependencies and license, then set PackageRelativePath. See the enterprise guide." }
    $package = Resolve-EnterpriseFile $PackageRelativePath
    $dependencies = @($DependencyRelativePaths | ForEach-Object { Resolve-EnterpriseFile $_ })
    $args = @{ Online=$true; PackagePath=$package; ErrorAction='Stop'; LogPath=(Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID + '-DISM.log')) }
    if ($dependencies.Count) { $args.DependencyPackagePath = [string[]]$dependencies }
    if ($LicenseRelativePath) { $args.LicensePath = Resolve-EnterpriseFile $LicenseRelativePath }
    elseif ($AllowUnlicensedPackage) { $args.SkipLicense = $true }
    else { throw 'Supply LicenseRelativePath. AllowUnlicensedPackage is only for packages confirmed to permit unlicensed offline provisioning.' }
    Set-EnterpriseProgress "Provisioning $Name; servicing log: $($args.LogPath)"
    # Windows deployment validates the package signature and dependencies. Do not bypass it.
    Add-AppxProvisionedPackage @args | Out-Null
    if (-not (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid)) {
        Set-EnterpriseProgress "Registering $Name for the signed-in user."
        Invoke-EnterpriseUserAction -UserSid $UserSid -Request @{ Action='InstallAppx'; PackagePath=$package; Dependencies=$dependencies }
    }
    if (-not (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid)) { throw "$Name is not healthy/registered for the signed-in user after installation." }
    Set-EnterpriseProgress "$Name installation verified."
}

function Install-EnterpriseStoreAppWithWinGetFallback {
    param([string]$Name, [string]$UserSid, [string]$PackageRelativePath = '',
        [string[]]$DependencyRelativePaths = @(), [string]$LicenseRelativePath = '',
        [bool]$AllowUnlicensedPackage = $false,
        [ValidateRange(30,1200)][int]$WinGetTimeoutSeconds = 600,
        [ValidateRange(0,120)][int]$WinGetVerifySeconds = 30)
    $storeIds = @{ 'Microsoft.CompanyPortal'='9WZDNCRFJ3PZ'; 'Microsoft.WindowsNotepad'='9MSMLRH6LZF3' }
    if (-not $storeIds.ContainsKey($Name)) { throw "No approved Store ID is configured for $Name." }
    if (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid) { Set-EnterpriseProgress "$Name is already available."; return }
    $attemptId = [Guid]::NewGuid().ToString('N')
    Set-EnterpriseProgress "Trying WinGet for $Name in the signed-in user's session."
    Write-EnterpriseLog "WinGet Store ID: $($storeIds[$Name]); source: msstore; target SID: $UserSid; timeout: $WinGetTimeoutSeconds seconds."
    Write-EnterpriseLog "Detailed WinGet logs are in that user's %LOCALAPPDATA%\PostEnrollmentSetupUI\WinGet\$attemptId."
    $wingetOutcome = 'WinGet returned success, but the app did not pass user-registration verification.'
    try {
        Invoke-EnterpriseUserAction -UserSid $UserSid -TimeoutSeconds ($WinGetTimeoutSeconds + 90) -Request @{
            Action='InstallStoreWithWinGet'; PackageId=$storeIds[$Name]; AttemptId=$attemptId; WinGetTimeoutSeconds=$WinGetTimeoutSeconds
        }
    }
    catch {
        if ($_.Exception.Data.Contains('DoNotFallback') -and $_.Exception.Data['DoNotFallback']) { throw }
        $wingetOutcome = $_.Exception.Message
        Write-EnterpriseLog -Level WARN -Message "WinGet attempt did not finish successfully: $wingetOutcome"
    }
    # The protected SYSTEM process checks registration independently. Native exit
    # zero, a user log, or a staged package alone can never produce success here.
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid) {
            Set-EnterpriseProgress "$Name is now installed and verified; offline fallback is not needed."
            return
        }
        if ($watch.Elapsed.TotalSeconds -ge $WinGetVerifySeconds) { break }
        Start-Sleep -Seconds 2
    } while ($true)
    Write-EnterpriseLog -Level WARN -Message $wingetOutcome
    Set-EnterpriseProgress "Trying the offline package for $Name."
    try {
        Install-EnterpriseStoreApp -Name $Name -UserSid $UserSid -PackageRelativePath $PackageRelativePath -DependencyRelativePaths $DependencyRelativePaths -LicenseRelativePath $LicenseRelativePath -AllowUnlicensedPackage $AllowUnlicensedPackage
    }
    catch { throw "WinGet did not produce a verified $Name installation. Offline fallback failed: $($_.Exception.Message) WinGet outcome: $wingetOutcome" }
    if (-not (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid)) { throw "Offline fallback returned, but $Name is not installed/healthy for the target user." }
}

function Wait-EnterpriseStoreApp {
    param([string]$Name, [string]$UserSid, [ValidateRange(0,3600)][int]$WaitSeconds = 300)
    Set-EnterpriseProgress "Waiting up to $WaitSeconds seconds for Intune to install $Name."
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (Test-EnterpriseUserApp -Name $Name -UserSid $UserSid) { Set-EnterpriseProgress "$Name is available."; return }
        if ($watch.Elapsed.TotalSeconds -ge $WaitSeconds) { break }
        Start-Sleep -Seconds 5
    } while ($true)
    throw "$Name remains missing. Check the Intune Required assignment, install status and Store connectivity. This mode observes deployment; it does not trigger an Intune install."
}
