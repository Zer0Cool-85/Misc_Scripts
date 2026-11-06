#Requires -Version 5.1
<# Isolated Windows PowerShell fixtures. No deployment, registry, scheduled
   task, online update, or reboot takes place. Run in a new process. #>
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixtureDir=Join-Path ([IO.Path]::GetTempPath()) ('FirstLogonMocks-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureDir)
function Assert-Case { param([bool]$Pass,[string]$Text); if (-not $Pass) { throw "FAIL: $Text" }; Write-Host "PASS: $Text" }
try {
    # Copy production entry points; replace only the injected platform dependencies.
    foreach ($name in @('Step-RemovePreinstalledOfficeOneDrive.ps1','Step-UpdateOtherApps.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root ('EnterpriseSteps/'+$name)) -Destination $fixtureDir
    }
    @'
function Set-EnterpriseProgress { param($Message) }
function Write-EnterpriseLog { param($Message,$Level) }
function Resolve-EnterpriseFile { param($RelativePath); return 'C:\fixture\GetHelpCmd.exe' }
function Assert-MicrosoftBinary { param($Path) }
function Get-EnterpriseUserSid { param($TargetUserSid); 'S-1-12-1-101-202-303-404' }
function Invoke-EnterpriseUserAction { param($UserSid,$Request,$TimeoutSeconds); if ($Request.Action -ne 'UpgradeUserApps') { throw 'unexpected user action' }; $global:PE10Fixture.UserCalls++; if ($global:PE10Fixture.Deny) { throw 'Simulated policy denial' } }
'@ | Set-Content -LiteralPath (Join-Path $fixtureDir 'Enterprise.Common.ps1') -Encoding UTF8
    @'
function Get-OfficeDesktopEvidence { if ($global:PE10Fixture.Office) { 'ARP: Microsoft Office Professional Plus 2016' } }
'@ | Set-Content -LiteralPath (Join-Path $fixtureDir 'Provisioning.Common.ps1') -Encoding UTF8
    $global:PE10Fixture=@{Office=$true;Receipt=$false;ToolCalls=0;Uninstalls=$true;UserCalls=0;Deny=$false;StateValue=16;Installs=0;Copies=0}
    $env:SETUP_RUN_DIRECTORY=$fixtureDir; $env:SETUP_STEP_ID='fixture';$env:SETUP_PACKAGE_ROOT=$fixtureDir
    & {
        function Test-Path { param($LiteralPath,$Path,$PathType); $v=if ($LiteralPath) { $LiteralPath } else { $Path }; if ($v -like '*OfficeBaseline') { return $global:PE10Fixture.Receipt }; return $false }
        function Get-Item { param($LiteralPath); $k=New-Object PSObject; $k | Add-Member ScriptMethod GetValue {param($name) 1}; $k }
        function New-Item { param($Path,[switch]$Force); if ($Path -notlike '*OfficeBaseline') { throw 'Unexpected registry target' } }
        function New-ItemProperty { param($LiteralPath,$Name,$PropertyType,$Value,[switch]$Force); if ($Name -ne 'AllDesktopOfficeRemoved') {throw 'Unexpected registry write'}; $global:PE10Fixture.Receipt=$true }
        function Get-Process { param($Name,$ErrorAction) }
        function Get-AppxPackage { param([switch]$AllUsers,$Name,$PackageTypeFilter,$ErrorAction) }
        function Get-AppxProvisionedPackage { param([switch]$Online,$ErrorAction) }
        function Remove-AppxPackage { throw 'No Store matches in this fixture' }
        function Remove-AppxProvisionedPackage { throw 'No Store matches in this fixture' }
        function Start-Sleep { param($Seconds) }
        function Start-Process {
            param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,[switch]$Wait,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError,$ErrorAction)
            if ($ArgumentList -ne '-S OfficeScrubScenario -AcceptEula -OfficeVersion All') {throw 'Unexpected native operation'}
            $global:PE10Fixture.ToolCalls++
            if ($global:PE10Fixture.Uninstalls) { $global:PE10Fixture.Office=$false }
            [pscustomobject]@{ExitCode=0}
        }
        $file=Join-Path $fixtureDir 'Step-RemovePreinstalledOfficeOneDrive.ps1'
        & $file -OfficeRemovalMode AllOffice -AuditOnly $true -RemoveOneDrive $false
        Assert-Case ($global:PE10Fixture.ToolCalls -eq 0 -and -not $global:PE10Fixture.Receipt) 'Office audit neither uninstalls nor writes a receipt'
        & $file -OfficeRemovalMode AllOffice -RemoveOneDrive $false
        Assert-Case ($global:PE10Fixture.ToolCalls -eq 1 -and $global:PE10Fixture.Receipt) 'Verified legacy cleanup creates one provisioning receipt'
        $global:PE10Fixture.Office=$true
        & $file -OfficeRemovalMode AllOffice -RemoveOneDrive $false
        Assert-Case ($global:PE10Fixture.Office -and $global:PE10Fixture.ToolCalls -eq 1) 'Later licensed install survives a rerun'
        $global:PE10Fixture.Receipt=$false;$global:PE10Fixture.Uninstalls=$false;$failed=$false
        try { & $file -OfficeRemovalMode AllOffice -RemoveOneDrive $false } catch { $failed=$true }
        Assert-Case ($failed -and -not $global:PE10Fixture.Receipt) 'Native exit zero with remaining Office cannot mark the baseline complete'
    }
    $file=Join-Path $fixtureDir 'Step-UpdateOtherApps.ps1'
    $global:LASTEXITCODE=0
    & $file -RunMachineUpdates $false -RunUserUpdates $true
    Assert-Case ($global:PE10Fixture.UserCalls -eq 1 -and $LASTEXITCODE -eq 0) 'Successful scoped update completes'
    $global:PE10Fixture.Deny=$true
    & $file -RunMachineUpdates $false -RunUserUpdates $true
    Assert-Case ($LASTEXITCODE -eq 20001) 'Policy denial from user WinGet becomes the configured neutral-skip exit'
    # Exercise the actual Google update state machine with one synthetic app.
    & {
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'EnterpriseSteps/Step-GoogleWorkspaceApps.ps1'),[ref]$tokens,[ref]$errors)
        $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Confirm-GoogleUpdate'},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
        function Write-EnterpriseLog { param($Message) }
        function Test-Path { param($LiteralPath); return $true }
        function Start-Sleep { param($Seconds) }
        function New-Object {
            param($ComObject,$ErrorAction)
            if ($ComObject -ne 'GoogleUpdate.Update3WebMachine') { throw 'Unexpected COM request' }
            $server=[pscustomobject]@{}
            $server | Add-Member ScriptMethod createAppBundleWeb {
                $bundle=[pscustomobject]@{}
                $bundle | Add-Member ScriptMethod initialize { return }
                $bundle | Add-Member ScriptMethod createInstalledApp {param($id)}
                $bundle | Add-Member ScriptMethod appWeb {param($i)
                    $a=[pscustomobject]@{}
                    $a | Add-Member ScriptProperty currentState {
                        $n=$global:PE10Fixture.States.Dequeue()
                        [pscustomobject]@{stateValue=$n;availableVersion='2.0';errorCode=5}
                    }; $a
                }
                $bundle | Add-Member ScriptMethod checkForUpdate { return }
                $bundle | Add-Member ScriptMethod install { $global:PE10Fixture.Installs++ }
                $bundle | Add-Member ScriptMethod cancel { return }
                $bundle
            }; $server
        }
        $global:PE10Fixture.States=[Collections.Queue]::new();foreach ($v in @(4,14,16)) {$global:PE10Fixture.States.Enqueue($v)}
        Confirm-GoogleUpdate Chrome 30
        Assert-Case ($global:PE10Fixture.Installs -eq 1 -and $global:PE10Fixture.States.Count -eq 0) 'Google available -> install -> recheck -> no update'
        $global:PE10Fixture.States.Enqueue(17); $failed=$false
        try { Confirm-GoogleUpdate Drive 30 } catch { $failed=$true }
        Assert-Case $failed 'Google check errors are not reported as current'
        foreach ($v in @(4,14,4)) {$global:PE10Fixture.States.Enqueue($v)}
        $failed=$false; try {Confirm-GoogleUpdate Drive 30} catch {$failed=$true}
        Assert-Case $failed 'A still-offered version fails freshness verification'
    }
} finally { Remove-Variable PE10Fixture -Scope Global -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $fixtureDir -Recurse -Force }
Write-Host 'Enterprise workflow mock tests passed.'
