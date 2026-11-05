[CmdletBinding()]
param(
    [ValidateSet('WinGetThenOffline','OfflinePackage','IntuneWait','WindowsCapability')][string]$Mode = 'WinGetThenOffline',
    [string]$TargetUserSid = '',
    [string]$PackageRelativePath = '',
    [string[]]$DependencyRelativePaths = @(),
    [string]$LicenseRelativePath = '',
    [bool]$AllowUnlicensedPackage = $false,
    [ValidateRange(0,3600)][int]$WaitSeconds = 300,
    [string]$CapabilitySource = '',
    [bool]$LimitAccess = $false,
    [ValidateRange(30,1200)][int]$WinGetTimeoutSeconds = 600,
    [ValidateRange(0,120)][int]$WinGetVerifySeconds = 30
)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
try {
    $sid = Get-EnterpriseUserSid $TargetUserSid
    if (Test-EnterpriseUserApp -Name 'Microsoft.WindowsNotepad' -UserSid $sid) { Set-EnterpriseProgress 'Windows Notepad is already available.'; return }
    switch ($Mode) {
        'WinGetThenOffline' { Install-EnterpriseStoreAppWithWinGetFallback -Name 'Microsoft.WindowsNotepad' -UserSid $sid -PackageRelativePath $PackageRelativePath -DependencyRelativePaths $DependencyRelativePaths -LicenseRelativePath $LicenseRelativePath -AllowUnlicensedPackage $AllowUnlicensedPackage -WinGetTimeoutSeconds $WinGetTimeoutSeconds -WinGetVerifySeconds $WinGetVerifySeconds }
        'IntuneWait' { Wait-EnterpriseStoreApp -Name 'Microsoft.WindowsNotepad' -UserSid $sid -WaitSeconds $WaitSeconds }
        'OfflinePackage' { Install-EnterpriseStoreApp -Name 'Microsoft.WindowsNotepad' -UserSid $sid -PackageRelativePath $PackageRelativePath -DependencyRelativePaths $DependencyRelativePaths -LicenseRelativePath $LicenseRelativePath -AllowUnlicensedPackage $AllowUnlicensedPackage }
        'WindowsCapability' {
            $caps = @(Get-WindowsCapability -Online -Name 'Microsoft.Windows.Notepad*' -ErrorAction Stop)
            if (-not $caps.Count) { throw 'This Windows image does not expose the classic Notepad capability. Use the modern Store package instead.' }
            if (@($caps | Where-Object State -eq 'Installed').Count) { Set-EnterpriseProgress 'Classic Notepad capability is already installed.'; return }
            if ($caps.Count -ne 1) { throw 'Multiple Notepad capabilities found; review the image before installing.' }
            $args = @{Online=$true; Name=$caps[0].Name; ErrorAction='Stop'; LogPath=(Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID + '-DISM.log'))}
            if ($CapabilitySource) { $args.Source = $CapabilitySource }
            if ($LimitAccess) { $args.LimitAccess = $true }
            Set-EnterpriseProgress 'Installing the classic Windows Notepad capability.'
            $result = Add-WindowsCapability @args
            if ($result.RestartNeeded) { $global:SetupUiRebootRequired = $true }
            if ((Get-WindowsCapability -Online -Name $caps[0].Name).State -ne 'Installed') { throw 'Notepad capability did not reach Installed state.' }
            Set-EnterpriseProgress 'Classic Notepad capability installation verified.'
        }
    }
}
catch { Write-EnterpriseLog -Level ERROR -Message $_.Exception.Message; throw }
