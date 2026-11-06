[CmdletBinding()]
param([bool]$RunMachineUpdates=$true,[bool]$RunUserUpdates=$true,
      [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$MachineSource='winget',
      [string[]]$ExcludeMachineIds=@('Google.Chrome','Google.GoogleDrive'),
      [ValidateRange(30,1800)][int]$MachineTimeoutSeconds=900,
      [ValidateRange(30,1200)][int]$UserTimeoutSeconds=300,[string]$TargetUserSid='')
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
# 20001 is a neutral skip ONLY on steps explicitly configured to accept it.
$issues=@();$uncertain=$false
if ($RunMachineUpdates) {
    try {
        Set-EnterpriseProgress 'Checking machine applications for updates.'
        $req=@{Source=$MachineSource;ExcludeIds=@($ExcludeMachineIds)} | ConvertTo-Json -Compress
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($req))
        $argsLine='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestBase64 {1}' -f (Join-Path $PSScriptRoot 'Invoke-MachinePackageUpdates.ps1'),$encoded
        $proc=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argsLine -WindowStyle Hidden -PassThru -ErrorAction Stop
        $null=$proc.Handle
        try {
            if (-not $proc.WaitForExit($MachineTimeoutSeconds*1000)) {
                $uncertain=$true
                $killer=Start-Process (Join-Path $env:SystemRoot 'System32/taskkill.exe') -ArgumentList ("/PID {0} /T /F" -f $proc.Id) -PassThru -WindowStyle Hidden -ErrorAction Stop
                try { $null=$killer.Handle; [void]$killer.WaitForExit(10000) } finally { $killer.Dispose() }
                throw 'Machine update timed out. Further update attempts were deferred; servicing may continue independently.'
            }
            if ($proc.ExitCode -eq 3010) { $global:SetupUiRebootRequired=$true }
            elseif ($null -eq $proc.ExitCode -or $proc.ExitCode -ne 0) { throw "Machine update worker returned $($proc.ExitCode). See SetupUI.log." }
        } finally { $proc.Dispose() }
    } catch { $issues+=$_.Exception.Message }
}
if ($RunUserUpdates -and -not $uncertain) {
    try {
        $sid=Get-EnterpriseUserSid $TargetUserSid
        $attempt=[guid]::NewGuid().ToString('N')
        Set-EnterpriseProgress 'Checking applications installed for the signed-in user.'
        Write-EnterpriseLog "User WinGet scan: target $sid; log folder in user's %LOCALAPPDATA%\PostEnrollmentSetupUI\WinGet\$attempt"
        Invoke-EnterpriseUserAction -UserSid $sid -Request @{Action='UpgradeUserApps';PackageId='user-scope upgrades';AttemptId=$attempt;WinGetTimeoutSeconds=$UserTimeoutSeconds} -TimeoutSeconds ($UserTimeoutSeconds+90)
    } catch { $issues+=$_.Exception.Message }
}
if (-not $RunMachineUpdates -and -not $RunUserUpdates) { $issues+='Both scans were disabled.' }
if ($issues.Count) {
    foreach ($message in $issues) { Write-EnterpriseLog -Level WARN -Message $message }
    Set-EnterpriseProgress 'Remaining app updates will be handled by normal device maintenance.'
    exit 20001
}
Set-EnterpriseProgress 'Application update checks completed.'
