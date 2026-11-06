#Requires -Version 5.1
<# Run in a fresh 64-bit Windows PowerShell process. No elevation is necessary.
   All native restart calls are mocked; no installers, registry or tasks are used. #>
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Core/Setup.Common.ps1')
. (Join-Path $root 'EnterpriseSteps/Provisioning.Common.ps1')
function Check { param([bool]$Ok,[string]$Label); if (-not $Ok) { throw "FAIL: $Label" }; Write-Host "PASS: $Label" }
function Reject { param([scriptblock]$Run,[string]$Label); $failed=$false; try { & $Run | Out-Null } catch { $failed=$true }; Check $failed $Label }
function Name-Example { param($Template,$Serial='PF-1A2B3C4D',$Id='d85b1407-351d-4694-9392-03acc5870eb1'); Get-DeviceNameValue $Template 'AC' 'CLE' 'L' $Serial 'AS-12345' $Id }
Check ((Name-Example '{Prefix}-{Type}{Serial:7}') -eq 'AC-LA2B3C4D') 'Deterministic serial tail, normalized firmware, laptop type'
Check ((Name-Example '{Site}-{Asset:4}') -eq 'CLE-2345') 'Site and asset tag'
Check ((Name-Example '{Prefix}-{Hash:8}') -match '^AC-[0-9A-F]{8}$') 'UUID hash template'
Reject { Name-Example '{Prefix}-{Serial}' 'To Be Filled By O.E.M.' } 'Placeholder serial cannot rename a PC'
Reject { Name-Example '{Prefix}-{Hash:8}' '' '00000000-0000-0000-0000-000000000000' } 'Empty UUID is rejected'
foreach ($invalid in @('{Unknown}', '012345', 'TOO-LONG-FOR-NETBIOS', 'BAD-', 'CON')) { Reject {Name-Example $invalid} "Reject invalid result $invalid" }
Check ((Get-ProvisionVendor 'Dell Inc.') -eq 'Dell' -and (Get-ProvisionVendor 'LENOVO') -eq 'Lenovo' -and (Get-ProvisionVendor 'Hewlett-Packard') -eq 'HP' -and (Get-ProvisionVendor 'Other builder') -eq 'Other') 'OEM routing'
Check ((Get-EncryptionVerdict FullyEncrypted Off $false) -eq 'NeedsAttention') 'Suspended protection is not compliance'
Check ((Get-EncryptionVerdict FullyEncrypted On $false) -eq 'Protected') 'Encrypted OS volume with protection on'
Check ((Get-EncryptionVerdict EncryptionInProgress On $false) -eq 'NeedsAttention' -and (Get-EncryptionVerdict EncryptionInProgress On $true) -eq 'Encrypting') 'In-progress policy distinction'
$cfg=Read-SetupConfiguration (Join-Path $root 'Config/Enterprise-FirstLogon.json') $root
$old=Read-SetupConfiguration (Join-Path $root 'Config/Setup.json') $root
Check ($cfg.Steps.Count -eq 10 -and $cfg.Behavior.EnforceFinalRestart -and -not $old.Behavior.EnforceFinalRestart) 'Restart opt-in and ten-step config'
$opt=[pscustomobject]@{Status='MaintenanceSkipped';Definition=[pscustomobject]@{Required=$false}}
$req=[pscustomobject]@{Status='Complete';Definition=[pscustomobject]@{Required=$true}}
Check ((Get-SetupOutcome @($req,$opt)) -eq 'Success') 'Deferred patching does not produce a warning'
$opt.Status='Skipped'; Check ((Get-SetupOutcome @($req,$opt)) -eq 'Warning') 'Ordinary dependency skip retains its warning'
$req.Status='Failed'; Check ((Get-SetupOutcome @($req,$opt)) -eq 'Failed') 'Required failures still block'
$update=@($cfg.Steps | Where-Object Id -eq 'updates')[0]
$saved=@{Completed=@{updates=[pscustomobject]@{Fingerprint='same';Disposition='MaintenanceSkipped'}};Declined=@{}}
Check ((Get-SetupResumeStatus $update 'same' $saved) -eq 'MaintenanceSkipped' -and (Get-SetupResumeStatus $update 'changed' $saved) -eq 'Pending') 'Neutral skip is remembered only for this fingerprint'
Check (Test-SetupRestartEligible $false $true $true Success '' $false) 'Successful live setup may schedule restart'
Check (-not (Test-SetupRestartEligible $true $true $true Success '' $false)) 'Demo never schedules'
Check (-not (Test-SetupRestartEligible $false $true $true Failed '' $false)) 'Required failure never schedules'
Check (-not (Test-SetupRestartEligible $false $true $true Warning 'controller fault' $false)) 'Controller failure never schedules'
Check (-not (Test-SetupRestartEligible $false $true $true Success '' $true)) 'Worker timeout never schedules'
Check (-not (Test-SetupRestartEligible $false $true $false Success '' $false)) 'No request after later boot: no second restart'
# Execute the real scheduler function with Start-Process shadowed. The real host
# and its WPF startup code are never invoked.
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Start-DeviceSetup.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors -join '; ') }
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-SetupFinalRestart'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
function Start-Process { param($FilePath,$ArgumentList,$WindowStyle,[switch]$Wait,[switch]$PassThru,$ErrorAction); $script:calls+=,$ArgumentList; [pscustomobject]@{ExitCode=$script:nativeCode} }
function Save-RunReport {}
function Write-RunLog { param($Message) }
$folder=Join-Path ([IO.Path]::GetTempPath()) ('RestartFixture-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
try {
    $identity=[pscustomobject]@{IsSystem=$true}; $script:config=$cfg
    $script:ui=@{};foreach($n in @('RebootMessage','RetryButton','CloseButton','OverallHeading','OverallMessage')) { $script:ui[$n]=[pscustomobject]@{Text='';Content='';Visibility=''} }
    $script:statePath=Join-Path $folder 'Completed.json'; $script:bootStamp='boot-one'
    $script:calls=@();$script:nativeCode=0;$script:restartEligible=$true;$script:restartArmed=$false;$script:restartDeadline=$null;$script:isDemo=$true
    Start-SetupFinalRestart; Check ($script:calls.Count -eq 0) 'No native restart from demo even if eligibility is accidentally set'
    $script:isDemo=$false
    Start-SetupFinalRestart; Start-SetupFinalRestart
    Check ($script:calls.Count -eq 1 -and $script:calls[0] -match '/r /f /t \d+' -and $script:restartArmed) 'Live success schedules exactly one OS countdown'
    $deadline=$script:restartDeadline
    $script:restartArmed=$false;$script:nativeCode=1190;$script:restartDeadline=$null
    Start-SetupFinalRestart
    Check ($script:restartArmed -and $script:restartDeadline -eq $deadline) 'Same-boot relaunch keeps the original deadline'
    $script:restartArmed=$false;$script:restartDeadline=$null;$script:bootStamp='boot-two';$script:nativeCode=5
    Start-SetupFinalRestart
    Check ($script:restartScheduleFailed -and -not $script:restartArmed -and $script:exitCode -eq 1) 'Scheduling rejection cannot appear as success'
} finally { Remove-Item -LiteralPath $folder -Recurse -Force }
Write-Host 'Provisioning regression tests passed. A live Windows/ServiceUI pilot is separate.'
