#requires -Version 5.1
# Offline tests. Import definitions only; never call the Windows entry point.
# No toast is shown and no real shutdown process can be started by these tests.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'Source/User-RebootToast.ps1'
$text = [IO.File]::ReadAllText($path)
$offset = $text.IndexOf('# MAIN:')
if ($offset -lt 0) { throw 'Entry-point boundary missing.' }
. ([scriptblock]::Create($text.Substring(0, $offset)))
$script:Checks = 0
function Assert-Equal {
    param($Actual,$Expected,[string]$Label)
    if ($Actual -cne $Expected) { throw "$Label expected [$Expected], got [$Actual]" }
    $script:Checks++
}
$token = '0123456789abcdef0123456789abcdef'
$state = [pscustomobject]@{ Active='DESKTOP-123'; Target='JDOE-LT-AA'; Pending=$true }
function New-ValidRecord {
    [pscustomobject]@{ Token=$token; Active='DESKTOP-123'; Target='JDOE-LT-AA'; Preview=$false; Consumed=$false; ExpiresTicks=[DateTime]::UtcNow.AddDays(1).Ticks.ToString() }
}

$tokens=$null; $errors=$null
$ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
Assert-Equal @($errors).Count 0 'Actual PowerShell parser'
$native = $ast.Find({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.StartsWith('using System;') },$true)
Add-Type -TypeDefinition $native.Value -ErrorAction Stop
$script:Checks++

$xml = [xml](New-RenameToastXml -Token $token)
Assert-Equal $xml.toast.scenario 'reminder' 'Reminder scenario'
Assert-Equal $xml.toast.activationType 'protocol' 'Body never directly restarts'
Assert-Equal $xml.toast.actions.input.defaultInput '15' 'Default snooze'
Assert-Equal (($xml.toast.actions.input.selection | ForEach-Object { $_.id }) -join ',') '15,60,240' 'Snooze choices'
$actions=@($xml.toast.actions.action)
Assert-Equal $actions.Count 2 'Two action buttons'
Assert-Equal $actions[0].activationType 'system' 'Windows handles Snooze'
Assert-Equal $actions[0].arguments 'snooze' 'Native snooze action'
Assert-Equal $actions[0].'hint-inputId' 'snoozeTime' 'Snooze connected to selection'
Assert-Equal $actions[1].activationType 'protocol' 'Restart invokes guarded user handler'
Assert-Equal $actions[1].arguments ("devicerename-reboot://restart/$token") 'Restart carries current token'
Assert-Equal (([xml](New-RenameToastXml -Token $token -IsPreview)).toast.visual.binding.text[0]) 'Preview: restart reminder' 'Preview is labeled'

Assert-Equal (Test-RestartAuthorization (New-ValidRecord) $state $token) $true 'Valid explicit action'
Assert-Equal (Test-RestartAuthorization $null $state $token) $false 'No saved consent context'
Assert-Equal (Test-RestartAuthorization (New-ValidRecord) $null $token) $false 'Unknown machine state'
Assert-Equal (Test-RestartAuthorization (New-ValidRecord) $state ('f'*32)) $false 'Wrong token'
$record=New-ValidRecord; $record.Preview=$true
Assert-Equal (Test-RestartAuthorization $record $state $token) $false 'Preview never restarts'
$record=New-ValidRecord; $record.Consumed=$true
Assert-Equal (Test-RestartAuthorization $record $state $token) $false 'Repeated click rejected'
$record=New-ValidRecord; $record.ExpiresTicks=[DateTime]::UtcNow.AddSeconds(-1).Ticks.ToString()
Assert-Equal (Test-RestartAuthorization $record $state $token) $false 'Expired action rejected'
$record=New-ValidRecord; $record.Target='SOMEONE-ELSE'
Assert-Equal (Test-RestartAuthorization $record $state $token) $false 'Another pending target rejected'
$complete=[pscustomobject]@{ Active='JDOE-LT-AA'; Target='JDOE-LT-AA'; Pending=$false }
Assert-Equal (Test-RestartAuthorization (New-ValidRecord) $complete $token) $false 'Post-reboot click ignored'
$unknown=[pscustomobject]@{ Token=$token; Active=$state.Active; Target=$state.Target; ExpiresTicks='invalid' }
Assert-Equal (Test-RestartAuthorization $unknown $state $token) $false 'Incomplete state fails closed'
foreach($uri in @('https://example.com','devicerename-reboot://restart/anything',"devicerename-reboot://restart/$token?command=whoami",'devicerename-reboot://shutdown/'+$token)) {
    Assert-Equal ($null -eq (Get-ToastActivation $uri)) $true 'Reject unsupported URI'
}
Assert-Equal (Get-ToastActivation "devicerename-reboot://open/$token").Action 'open' 'Open is separate from restart'

# Exercise the real action dispatcher with only its Windows boundaries mocked.
$script:ShutdownCalls=0
$script:ShutdownArguments=$null
$script:ShutdownExit=0
$script:CurrentRecord=New-ValidRecord
$script:CurrentState=$state
$script:Shown=0
function Read-ToastRecord { return $script:CurrentRecord }
function Save-ToastRecord { param($Record) $script:CurrentRecord=$Record }
function Get-ToastNameState { return $script:CurrentState }
function Write-ToastLog { param($Message) }
function Remove-RenameToast { }
function Show-RenameToast { param([switch]$IsPreview) $script:Shown++; $script:LastPreview=[bool]$IsPreview }
function Join-Path { param($Path,$ChildPath) return ($Path+'\'+$ChildPath) }
function Start-Process {
    param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru,$WindowStyle)
    $script:ShutdownCalls++
    $script:ShutdownArguments=$ArgumentList -join ' '
    [pscustomobject]@{ ExitCode=$script:ShutdownExit }
}
$env:WINDIR='C:\Windows'
Invoke-ToastActivation "devicerename-reboot://restart/$token"
Assert-Equal $script:ShutdownCalls 1 'Only explicit restart launches shutdown'
Assert-Equal $script:ShutdownArguments '/r /t 0' 'No forced close or implicit force via positive timeout'
Assert-Equal $script:CurrentRecord.Consumed $true 'Action consumed before shutdown'
Invoke-ToastActivation "devicerename-reboot://restart/$token"
Assert-Equal $script:ShutdownCalls 1 'Duplicate activation does not restart twice'
$script:CurrentRecord=New-ValidRecord; $script:CurrentState=$complete
Invoke-ToastActivation "devicerename-reboot://restart/$token"
Assert-Equal $script:ShutdownCalls 1 'Real dispatcher checks latest name state'
$script:CurrentState=$state; $script:CurrentRecord=New-ValidRecord; $script:CurrentRecord.Preview=$true
Invoke-ToastActivation "devicerename-reboot://restart/$token"
Assert-Equal $script:ShutdownCalls 1 'Preview dispatcher never launches shutdown'
Invoke-ToastActivation "devicerename-reboot://open/$token"
Assert-Equal $script:Shown 1 'Body click opens reminder'
Assert-Equal $script:LastPreview $true 'Body click retains preview safety'
$script:CurrentRecord=New-ValidRecord; $script:ShutdownExit=5
$failed=$false
try { Invoke-ToastActivation "devicerename-reboot://restart/$token" } catch { $failed=$true }
Assert-Equal $failed $true 'Denied restart is reported'
Assert-Equal $script:CurrentRecord.Consumed $false 'Failed restart can be retried'
Write-Output "PASS: $script:Checks toast/action checks. WinRT UI, COM shortcut installation, Task Scheduler and shutdown still require a Windows pilot."
