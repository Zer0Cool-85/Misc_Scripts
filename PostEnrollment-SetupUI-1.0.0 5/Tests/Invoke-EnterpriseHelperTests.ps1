#Requires -Version 5.1
<# Isolated helper checks. No app installs, HKLM writes, or scheduled tasks.
   Run in a fresh 64-bit powershell.exe process on Windows. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('EnterpriseHelperTest-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$env:SETUP_PACKAGE_ROOT = $root
$env:SETUP_RUN_DIRECTORY = $temp
$env:SETUP_STEP_ID = 'test'
. (Join-Path $root 'Core/Setup.Common.ps1')
. (Join-Path $root 'EnterpriseSteps/Enterprise.Common.ps1')
function Assert-Test { param([bool]$Pass, [string]$Message); if (-not $Pass) { throw "FAIL: $Message" }; Write-Host "PASS: $Message" }
$jobs = @()
try {
    # Two writers exercise the same append/retry helper used by UI and workers.
    $log = Join-Path $temp 'Concurrent.log'
    foreach ($writer in 1..2) {
        $jobs += Start-Job -ArgumentList $root,$log,$writer -ScriptBlock {
            param($root,$log,$writer)
            . (Join-Path $root 'Core/Setup.Common.ps1')
            1..50 | ForEach-Object { Add-SetupLogLine -Path $log -Line "$writer/$_" }
        }
    }
    $jobs | Wait-Job | Receive-Job -ErrorAction Stop
    $lines = @(Get-Content -LiteralPath $log)
    Assert-Test ($lines.Count -eq 100 -and @($lines | Sort-Object -Unique).Count -eq 100) 'Concurrent log writes preserve every complete line'

    $fixture = @{Present=$false; Status='Ok'; Partial=$false; Publisher='CN=Microsoft Corporation, O=Microsoft Corporation, C=US'; Calls=0; Provisions=0; UserInstalls=0; QueryError=$false; Metadata=$true; Users=@([pscustomobject]@{UserSecurityId='S-1-5-21-100-100-100-1001';InstallState='Installed'})}
    function Get-AppxPackage {
        param([switch]$AllUsers,$User,$Name,$ErrorAction)
        if (-not $AllUsers -or $PSBoundParameters.ContainsKey('User')) { throw 'Detection must use AllUsers and compare per-user registration.' }
        $fixture.Calls++
        if ($fixture.QueryError) { throw 'Simulated AppX inventory failure' }
        if ($fixture.Present) {
            $package = [pscustomobject]@{Name=$Name;Status=$fixture.Status;IsPartiallyStaged=$fixture.Partial;Publisher=$fixture.Publisher;PackageUserInformation=$fixture.Users}
            if (-not $fixture.Metadata) { $package.PSObject.Properties.Remove('PackageUserInformation') }
            $package
        }
    }
    function Set-EnterpriseProgress { param($Message) }
    function Resolve-EnterpriseFile { param($RelativePath); return (Join-Path $temp $RelativePath) }
    function Add-AppxProvisionedPackage { param([switch]$Online,$PackagePath,$LicensePath,$DependencyPackagePath,[switch]$SkipLicense,$LogPath,$ErrorAction); $fixture.Provisions++ }
    function Invoke-EnterpriseUserAction { param($UserSid,$Request); $fixture.UserInstalls++; $fixture.Present=$true }
    $sid = 'S-1-5-21-100-100-100-1001'
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Absent current-user app is missing'
    Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath 'Main.appxbundle' -LicenseRelativePath 'License.xml'
    Assert-Test ($fixture.Provisions -eq 1 -and $fixture.UserInstalls -eq 1) 'Provisioning alone does not count as current-user registration'
    Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath 'Main.appxbundle' -LicenseRelativePath 'License.xml'
    Assert-Test ($fixture.Provisions -eq 1 -and $fixture.UserInstalls -eq 1) 'Healthy registered app skips reinstall'
    $fixture.Users = @([pscustomobject]@{UserSecurityId='S-1-5-21-100-100-100-1002';InstallState='Installed'})
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Another user installation does not satisfy detection'
    $fixture.Users += [pscustomobject]@{UserSecurityId=$sid;InstallState='Staged'}
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Staged target plus installed other user is still missing for target'
    $fixture.Users[1].InstallState = 'Installed'
    Assert-Test (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid) 'Exact target Installed registration satisfies detection'
    $fixture.Users = @([pscustomobject]@{UserSecurityId='S-1-12-1-100-200-300-400';InstallState='Installed'})
    Assert-Test (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid 'S-1-12-1-100-200-300-400') 'Entra-format SID matches without account-name resolution'
    $fixture.Users = @([pscustomobject]@{UserSecurityId=$sid;InstallState='Installed'})
    $fixture.QueryError = $true
    $rejected=$false
    try { $null = Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid } catch { $rejected = $_.Exception.Message -like '*AppX inventory query failed*' }
    Assert-Test $rejected 'Inventory errors fail instead of returning app missing'
    $fixture.QueryError = $false; $fixture.Metadata = $false
    $rejected=$false
    try { $null = Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid } catch { $rejected = $_.Exception.Message -like '*PackageUserInformation*' }
    Assert-Test $rejected 'Missing per-user metadata fails instead of guessing'
    $fixture.Metadata = $true
    foreach ($badSid in @('not-a-sid','S-1-5-18')) {
        $beforeCalls = $fixture.Calls; $rejected=$false
        try { $null = Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $badSid } catch { $rejected=$true }
        Assert-Test ($rejected -and $fixture.Calls -eq $beforeCalls) 'Invalid/service SID is rejected before inventory'
    }
    $fixture.Partial=$true
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Partially staged app is not ready'
    $fixture.Partial=$false; $fixture.Status='Modified'
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Unhealthy app is not ready'
    $fixture.Status='Ok'; $fixture.Publisher='CN=Other Publisher'
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Wrong publisher is rejected'
    $fixture.Present=$false
    $rejected=$false
    try { Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath 'Main.appxbundle' } catch { $rejected=$true }
    Assert-Test ($rejected -and $fixture.Provisions -eq 1) 'Missing license is rejected before provisioning'
    Write-Host 'Helper tests passed. Live Windows install/removal tests remain separate.'
}
finally {
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
