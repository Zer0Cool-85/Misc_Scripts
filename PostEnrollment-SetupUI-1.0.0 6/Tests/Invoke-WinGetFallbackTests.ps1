#Requires -Version 5.1
<# Isolated orchestration checks. WinGet, AppX and scheduled tasks are mocked.
   Run in a fresh 64-bit Windows PowerShell process; no apps are installed. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('WinGetFallbackTest-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$env:SETUP_PACKAGE_ROOT = $root
$env:SETUP_RUN_DIRECTORY = $temp
$env:SETUP_STEP_ID = 'test'
. (Join-Path $root 'EnterpriseSteps/Enterprise.Common.ps1')

function Assert-Test {
    param([bool]$Pass, [string]$Message)
    if (-not $Pass) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}
function Reset-Fixture {
    $script:fixture = @{
        Present=$false; Checks=0; QueryErrorAt=0; WinGetCalls=0; OfflineCalls=0
        WinGetInstalls=$false; WinGetFails=$false; Unsafe=$false
        OfflineInstalls=$true; OfflineFails=$false; Request=$null; OfflineParameters=$null
    }
}
function Write-EnterpriseLog { param($Message,$Level) }
function Set-EnterpriseProgress { param($Message) }
function Test-EnterpriseUserApp {
    param($Name,$UserSid)
    $fixture.Checks++
    if ($fixture.Checks -eq $fixture.QueryErrorAt) { throw 'Simulated AppX inventory error' }
    return $fixture.Present
}
function Invoke-EnterpriseUserAction {
    param($UserSid,$Request,$TimeoutSeconds)
    $fixture.WinGetCalls++
    $fixture.Request = $Request
    if ($TimeoutSeconds -ne ($Request.WinGetTimeoutSeconds + 90)) { throw 'Incorrect outer timeout budget' }
    if ($fixture.WinGetInstalls) { $fixture.Present=$true }
    if ($fixture.Unsafe) {
        $failure = [TimeoutException]::new('Simulated uncertain cancellation')
        $failure.Data['DoNotFallback']=$true
        throw $failure
    }
    if ($fixture.WinGetFails) { throw 'Simulated WinGet failure/unavailable/denied' }
}
function Install-EnterpriseStoreApp {
    param($Name,$UserSid,$PackageRelativePath,$DependencyRelativePaths,$LicenseRelativePath,$AllowUnlicensedPackage)
    $fixture.OfflineCalls++
    $fixture.OfflineParameters = $PSBoundParameters
    if ($fixture.OfflineFails) { throw 'Simulated offline deployment failure' }
    if ($fixture.OfflineInstalls) { $fixture.Present=$true }
}

try {
    foreach ($case in @(
        @{Name='Microsoft.CompanyPortal';Id='9WZDNCRFJ3PZ'},
        @{Name='Microsoft.WindowsNotepad';Id='9MSMLRH6LZF3'}
    )) {
        $invoke = @{
            Name=$case.Name; UserSid='S-1-12-1-100-200-300-400'
            PackageRelativePath='Payloads/Main.msixbundle'
            DependencyRelativePaths=@('Payloads/Dependency.appx')
            LicenseRelativePath='Payloads/License.xml'; AllowUnlicensedPackage=$false
            WinGetTimeoutSeconds=60; WinGetVerifySeconds=0
        }
        Reset-Fixture
        $fixture.Present=$true
        Install-EnterpriseStoreAppWithWinGetFallback @invoke
        Assert-Test ($fixture.WinGetCalls -eq 0 -and $fixture.OfflineCalls -eq 0) "$($case.Name): existing healthy app skips both installers"

        Reset-Fixture
        $fixture.WinGetInstalls=$true
        Install-EnterpriseStoreAppWithWinGetFallback @invoke
        Assert-Test ($fixture.WinGetCalls -eq 1 -and $fixture.OfflineCalls -eq 0) "$($case.Name): verified WinGet result skips offline"
        Assert-Test ($fixture.Request.PackageId -eq $case.Id -and $fixture.Request.Action -eq 'InstallStoreWithWinGet') "$($case.Name): correct Store ID and limited-user action"

        Reset-Fixture
        $fixture.WinGetInstalls=$true; $fixture.WinGetFails=$true
        Install-EnterpriseStoreAppWithWinGetFallback @invoke
        Assert-Test ($fixture.OfflineCalls -eq 0 -and $fixture.Checks -ge 2) "$($case.Name): current registration wins even after a WinGet error"

        Reset-Fixture
        Install-EnterpriseStoreAppWithWinGetFallback @invoke
        Assert-Test ($fixture.OfflineCalls -eq 1 -and $fixture.Present) "$($case.Name): WinGet zero without a registered app falls back"
        Assert-Test ($fixture.OfflineParameters.PackageRelativePath -eq $invoke.PackageRelativePath -and $fixture.OfflineParameters.DependencyRelativePaths[0] -eq $invoke.DependencyRelativePaths[0] -and $fixture.OfflineParameters.LicenseRelativePath -eq $invoke.LicenseRelativePath -and -not $fixture.OfflineParameters.AllowUnlicensedPackage) "$($case.Name): fallback retains configured package, dependency and license"

        Reset-Fixture
        $fixture.WinGetFails=$true
        Install-EnterpriseStoreAppWithWinGetFallback @invoke
        Assert-Test ($fixture.OfflineCalls -eq 1 -and $fixture.Present) "$($case.Name): unavailable/denied WinGet falls back"

        Reset-Fixture
        $fixture.WinGetFails=$true; $fixture.OfflineFails=$true
        $message = ''
        try { Install-EnterpriseStoreAppWithWinGetFallback @invoke } catch { $message=$_.Exception.Message }
        Assert-Test ($message -like '*Offline fallback failed*' -and $message -like '*WinGet outcome*' -and -not $fixture.Present) "$($case.Name): dual failure reports both attempts"

        Reset-Fixture
        $fixture.OfflineInstalls=$false
        $failed=$false
        try { Install-EnterpriseStoreAppWithWinGetFallback @invoke } catch { $failed=$true }
        Assert-Test ($failed -and $fixture.OfflineCalls -eq 1) "$($case.Name): unverified offline return is a failure"

        foreach ($query in 1..2) {
            Reset-Fixture
            $fixture.QueryErrorAt=$query
            $message=''
            try { Install-EnterpriseStoreAppWithWinGetFallback @invoke } catch { $message=$_.Exception.Message }
            Assert-Test ($message -like '*AppX inventory error*' -and $fixture.OfflineCalls -eq 0) "$($case.Name): inventory error at check $query never means missing"
        }

        Reset-Fixture
        $fixture.Unsafe=$true
        $failed=$false
        try { Install-EnterpriseStoreAppWithWinGetFallback @invoke } catch { $failed=$_.Exception.Data.Contains('DoNotFallback') }
        Assert-Test ($failed -and $fixture.OfflineCalls -eq 0) "$($case.Name): uncertain cancellation prevents offline fallback"
    }
    Write-Host 'WinGet fallback orchestration tests passed. Real Windows/Store/policy tests remain separate.'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
