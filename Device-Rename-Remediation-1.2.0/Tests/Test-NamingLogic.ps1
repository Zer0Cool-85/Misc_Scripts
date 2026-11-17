#requires -Version 5.1
<#
Offline tests. Run in a NEW powershell.exe/pwsh process, not dot-sourced.
Registry, CIM, rename, files, sessions and Task Scheduler are mocked. This file never renames
the host or displays a popup. A real Windows/SYSTEM pilot is still required.
#>
$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent
$script:Passed = 0
function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -cne $Expected) { throw "$Label - expected [$Expected], got [$Actual]" }
    $script:Passed++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Equal $threw $true $Label
}

# Parse every shipped script with the actual PowerShell parser.
foreach ($file in Get-ChildItem -Path $kit -Filter '*.ps1' -Recurse) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert-Equal @($errors).Count 0 ("Parse " + $file.Name)
}
$commonPath = Join-Path $kit 'Source/Naming.Common.ps1'
. $commonPath
$script:Component = 'Tests'

# Compile the real P/Invoke declarations without calling Windows APIs.
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($commonPath, [ref]$tokens, [ref]$errors)
$native = $ast.Find({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.StartsWith('using System;') }, $true)
Add-Type -TypeDefinition ($native.Value -replace 'namespace DeviceNaming', 'namespace DeviceNamingValidation') -ErrorAction Stop
$script:Passed++

# Controlled substitute for user sessions; no platform API calls are made.
Add-Type -TypeDefinition @'
using System;
namespace DeviceNaming {
    public class UserSession { public int Id; public string Account; }
    public static class SessionDiscovery {
        public static int Calls;
        public static bool Fail;
        public static UserSession[] Sessions = new UserSession[0];
        public static UserSession[] ActiveUsers() { return Sessions; }
        public static void Notify(int id, string title, string message, int timeout) {
            if (Fail) throw new Exception("Mock messaging failure");
            Calls++;
        }
    }
}
'@

# Override only Windows file materialization and account translation in a
# temporary test copy. Production scheduling/requirement logic stays intact.
$testHooks = @'
function Get-RebootToastPayloadPath { return 'C:\Program Files\DeviceRenameRemediation\User-RebootToast.ps1' }
function Resolve-NotificationUserSid { param([string]$Account) return 'S-1-12-1-111-222-333-444' }
'@
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('RenameLogic-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -Path $testDirectory -ItemType Directory)
Copy-Item -Path (Join-Path $kit '*') -Destination $testDirectory -Recurse
$testCommon = Join-Path $testDirectory 'Source/Naming.Common.ps1'
Add-Content -LiteralPath $testCommon -Value $testHooks -Encoding UTF8
foreach ($file in Get-ChildItem -Path (Join-Path $testDirectory 'Intune') -Filter '*.ps1') {
    $text = [IO.File]::ReadAllText($file.FullName)
    $text = $text.Replace('# MAIN:', ($testHooks + "`n# MAIN:"))
    [IO.File]::WriteAllText($file.FullName, $text, (New-Object Text.UTF8Encoding($true)))
}
$kit = $testDirectory
$env:WINDIR = 'C:\Windows'

function Reset-Fixture {
    $global:RenameTestFixture = @{
        Active='DESKTOP-123'; Configured='DESKTOP-123'; Account='AzureAD\john.doe'
        Domain=$false; Model='Latitude 5550'; Manufacturer='Dell Inc.'; Role=0
        Chassis=@(10); Registry=@{}; Renames=0; Tasks=@(); ReadFailure=$false
        CimFailure=$false; RenameFailure=$false; WrongPostState=$false
        NotificationReadFailure=$false
    }
    [DeviceNaming.SessionDiscovery]::Calls = 0
    [DeviceNaming.SessionDiscovery]::Fail = $false
    $session = New-Object DeviceNaming.UserSession
    $session.Id = 1; $session.Account = 'AzureAD\john.doe'
    [DeviceNaming.SessionDiscovery]::Sessions = @($session)
}
function New-ScheduledTaskAction {
    param($Execute, $Argument)
    [pscustomobject]@{ Execute=$Execute; Argument=$Argument }
}
function New-ScheduledTaskPrincipal {
    param($UserId, $LogonType, $RunLevel)
    [pscustomobject]@{ UserId=$UserId; LogonType=$LogonType; RunLevel=$RunLevel }
}
function New-ScheduledTaskTrigger {
    param([switch]$Once, $At)
    [pscustomobject]@{ Once=[bool]$Once; At=$At; EndBoundary=$null }
}
function New-ScheduledTaskSettingsSet {
    param([switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,[switch]$StartWhenAvailable,$ExecutionTimeLimit,$MultipleInstances,$DeleteExpiredTaskAfter)
    [pscustomobject]@{ DeleteExpiredTaskAfter=$DeleteExpiredTaskAfter }
}
function Register-ScheduledTask {
    [CmdletBinding()]param($TaskName,$Action,$Trigger,$Principal,$Settings,$Description,[switch]$Force)
    if ([DeviceNaming.SessionDiscovery]::Fail) { throw 'Mock task registration failure' }
    [DeviceNaming.SessionDiscovery]::Calls++
    $global:RenameTestFixture.Tasks += [pscustomobject]@{ Name=$TaskName; Action=$Action; Trigger=$Trigger; Principal=$Principal; Settings=$Settings }
}
function Get-ItemPropertyValue {
    [CmdletBinding()]param([string]$LiteralPath, [string]$Name)
    $f = $global:RenameTestFixture
    if ($LiteralPath -like '*\Control\ComputerName\*') {
        if ($f.ReadFailure) { throw 'Mock registry read failure' }
        if ($LiteralPath -like '*\ActiveComputerName') { return $f.Active }
        return $f.Configured
    }
    if ($f.Registry.ContainsKey($LiteralPath) -and $f.Registry[$LiteralPath].ContainsKey($Name)) {
        return $f.Registry[$LiteralPath][$Name]
    }
    # Reproduce a provider's terminating missing-value error, even when the
    # caller supplies SilentlyContinue. The original mock missed this failure.
    $exception = New-Object System.Management.Automation.PSArgumentException -ArgumentList "Property $Name does not exist at path $LiteralPath"
    $record = New-Object System.Management.Automation.ErrorRecord -ArgumentList $exception, 'PropertyNotFound', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $Name
    $PSCmdlet.ThrowTerminatingError($record)
}
function Get-ItemProperty {
    [CmdletBinding()]param([string]$LiteralPath)
    $f = $global:RenameTestFixture
    if ($f.NotificationReadFailure) { throw [UnauthorizedAccessException]::new('Mock notification-key access denied') }
    if (-not $f.Registry.ContainsKey($LiteralPath)) { throw 'Mock registry key missing' }
    # Reading all properties of an existing key succeeds even with no SessionN.
    return [pscustomobject]$f.Registry[$LiteralPath]
}
function Test-Path {
    [CmdletBinding()]param([string]$LiteralPath)
    return $global:RenameTestFixture.Registry.ContainsKey($LiteralPath)
}
function Join-Path {
    [CmdletBinding()]param([string]$Path, [string]$ChildPath)
    if ($Path -match '^(HKLM:|[A-Za-z]:)') { return ($Path.TrimEnd('\') + '\' + $ChildPath) }
    return Microsoft.PowerShell.Management\Join-Path -Path $Path -ChildPath $ChildPath
}
function New-Item {
    [CmdletBinding()]param([string]$Path, [switch]$Force)
    if ($Force) { throw 'Test forbids recreating existing registry keys with Force.' }
    if (-not $global:RenameTestFixture.Registry.ContainsKey($Path)) { $global:RenameTestFixture.Registry[$Path] = @{} }
    return [pscustomobject]@{ Path=$Path }
}
function New-ItemProperty {
    [CmdletBinding()]param([string]$LiteralPath, [string]$Name, $Value, [string]$PropertyType, [switch]$Force)
    if (-not $global:RenameTestFixture.Registry.ContainsKey($LiteralPath)) { throw 'Mock parent key missing' }
    $global:RenameTestFixture.Registry[$LiteralPath][$Name] = $Value
}
function Get-CimInstance {
    [CmdletBinding()]param([string]$ClassName, $Property)
    $f = $global:RenameTestFixture
    if ($f.CimFailure) { throw 'Mock CIM failure' }
    if ($ClassName -eq 'Win32_ComputerSystem') {
        return [pscustomobject]@{ UserName=$f.Account; PartOfDomain=$f.Domain; Model=$f.Model; Manufacturer=$f.Manufacturer; DomainRole=$f.Role }
    }
    if ($ClassName -eq 'Win32_SystemEnclosure') { return [pscustomobject]@{ ChassisTypes=$f.Chassis } }
    throw 'Unexpected CIM class'
}
function Rename-Computer {
    [CmdletBinding()]param([string]$NewName, [switch]$Force, [switch]$PassThru)
    $f = $global:RenameTestFixture
    $f.Renames++
    if ($f.RenameFailure) { throw 'Mock rename failure' }
    if (-not $f.WrongPostState) { $f.Configured = $NewName }
    return [pscustomobject]@{ HasSucceeded=$true }
}
function Invoke-Subject {
    param([string]$RelativePath, [hashtable]$Arguments = @{})
    $output = @(& (Join-Path $kit $RelativePath) @Arguments)
    return [pscustomobject]@{ Code=$LASTEXITCODE; Output=($output -join '|') }
}

foreach ($name in @('DESKTOP-A1B2C3D','LAPTOP-7X8Y9Z0','desktop-abc1234','laptop-a','LAPTOP-12345678','DESKTOP-LT','LAPTOP-PC')) {
    Assert-Equal (Test-GenericWindowsComputerName $name) $true "Generic input $name"
}
foreach ($name in @('', 'DESKTOP-', 'LAPTOP-', 'DESKTOP-ABC-123', 'LAPTOP-ABC_123', 'XDESKTOP-123', 'JDOE-LT', 'JDOE-LT-R7', 'FINANCE-PC', 'DESKTOP-12345678', "DESKTOP-123`n")) {
    Assert-Equal (Test-GenericWindowsComputerName $name) $false "Protected input $name"
}
Assert-Equal (Test-GenericWindowsComputerName $null) $false 'Null name is not generic'

foreach ($name in @('JDOE-LT','JDOE-LT-R7','jdoe-lt-r7','A12345678-LT-99','JDOE-DT','JDOE-VM-AA','ABCDEFGH-SRV-00','ABCDEFGHI-SRV')) {
    Assert-Equal (Test-NamingConvention $name) $true "Accept $name"
}
foreach ($name in @('', 'DESKTOP-123', 'J-LT', 'JDOE-LT-X', 'JDOE-LT-XXX', 'ABCDEFGHIJ-LT', 'ABCDEFGHI-SRV-00', 'J_DOE-LT', 'JDOE-LT-R7-extra', "JDOE-LT`n")) {
    Assert-Equal (Test-NamingConvention $name) $false "Reject $name"
}
Assert-Equal (Get-UserNamePrefix 'AzureAD\john.doe') 'JDOE' 'Domain account'
Assert-Equal (Get-UserNamePrefix 'john.doe@example.com') 'JDOE' 'UPN account'
Assert-Equal (Get-UserNamePrefix "AzureAD\jose.o'neill") 'JONEILL' 'Apostrophe'
Assert-Equal (Get-UserNamePrefix ('jos' + [char]0x00e9 + '.garc' + [char]0x00ed + 'a')) 'JGARCIA' 'Diacritics'
foreach ($account in @('', 'SYSTEM', 'john', 'john.middle.doe', '.doe', 'john.')) {
    Assert-Throws { Get-UserNamePrefix $account } "Reject account $account"
}
foreach ($type in @('LT','DT','VM','SRV','PC')) {
    $name = New-CompliantComputerName 'A123456789012345' $type
    Assert-Equal (Test-NamingConvention $name) $true "Generated $type"
    Assert-Equal ($name.Length -le 15) $true "Length $type"
    $expected = 9
    if ($type -eq 'SRV') { $expected = 8 }
    Assert-Equal ($name.Split('-')[0].Length) $expected "Prefix budget $type"
}
Assert-Equal (New-CompliantComputerName 'JDOE' LT -NoRandomSuffix) 'JDOE-LT' 'No suffix'

$requirement = 'Intune/Requirement-RenameComputer.ps1'
$detection = 'Intune/Detect-RenameComputer.ps1'
$installer = 'Source/Install-RenameComputer.ps1'
foreach ($name in @('DESKTOP-A1B2C3D','LAPTOP-7X8Y9Z0','desktop-abc1234','DESKTOP-LT','LAPTOP-PC')) {
    Reset-Fixture
    $global:RenameTestFixture.Active = $name
    $global:RenameTestFixture.Configured = $name
    $r = Invoke-Subject $requirement
    Assert-Equal $r.Code 0 "Generic requirement exits successfully: $name"
    Assert-Equal $r.Output '1' "Generic requirement allows install: $name"
    Assert-Equal $global:RenameTestFixture.Renames 0 'Requirement only evaluates'
}
foreach ($name in @('CORP-LT-001','ACCOUNTING01','JDOE-LT-R7','FINANCE-PC','DESKTOP-ABC-1')) {
    Reset-Fixture
    $global:RenameTestFixture.Active = $name
    $global:RenameTestFixture.Configured = $name
    $global:RenameTestFixture.CimFailure = $true
    $r = Invoke-Subject $requirement
    Assert-Equal $r.Code 0 "Custom name excludes before user/CIM query: $name"
    Assert-Equal $r.Output '0' "Custom requirement not met: $name"
    Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 0 'No reminder when no rename pending'
}
foreach ($name in @('DESKTOP-LT','LAPTOP-PC')) {
    Reset-Fixture
    $global:RenameTestFixture.Active = $name
    $global:RenameTestFixture.Configured = $name
    $r = Invoke-Subject $installer
    Assert-Equal $r.Code 3010 "Generic prefix wins over old-format overlap: $name"
    Assert-Equal $global:RenameTestFixture.Renames 1 "Installer agrees with requirement: $name"
}
foreach ($name in @('CORP-LT-001','ACCOUNTING01')) {
    Reset-Fixture
    $global:RenameTestFixture.Active = $name
    $global:RenameTestFixture.Configured = $name
    $r = Invoke-Subject $installer
    Assert-Equal $r.Code 1618 "Installer defers a protected name: $name"
    Assert-Equal $global:RenameTestFixture.Renames 0 'Manual installer leaves custom name unchanged'
    Assert-Equal $global:RenameTestFixture.Registry.Count 0 'Skipped custom name has no new receipt'
}
Reset-Fixture
$global:RenameTestFixture.Active = 'CORP-LT-001'
$global:RenameTestFixture.Configured = 'CUSTOM-TARGET'
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'Pending rename takes priority on custom names too'
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 1 'Custom-name pending rename still queues toast'
Assert-Equal $global:RenameTestFixture.Renames 0 'Pending custom name is never overwritten'

Reset-Fixture
$r = Invoke-Subject $requirement
Assert-Equal $r.Code 0 'Eligible requirement exit'
Assert-Equal $r.Output '1' 'Eligible requirement output only'
Assert-Equal $global:RenameTestFixture.Renames 0 'Requirement never renames'

Reset-Fixture
$global:RenameTestFixture.Active = 'JDOE-LT'
$global:RenameTestFixture.Configured = 'JDOE-LT'
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'Compliant requirement'
$r = Invoke-Subject $detection
Assert-Equal $r.Code 1 'Pre-existing compliant PC has no receipt'
Assert-Equal $r.Output '' 'Not-detected output is empty'

Reset-Fixture
$global:RenameTestFixture.Configured = 'ANOTHER-NAME'
$r = Invoke-Subject $requirement
Assert-Equal $r.Code 0 'Pending requirement exit'
Assert-Equal $r.Output '0' 'Pending has priority even for noncompliant target'
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 1 'Pending rename queues toast task'
$r = Invoke-Subject $requirement
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 1 'Repeated checks do not override Snooze'
$r = Invoke-Subject $detection
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 1 'Detection shares once-only task history'
Assert-Equal $global:RenameTestFixture.Renames 0 'No rename over pending target'
$notificationKey = 'HKLM:\SOFTWARE\DeviceRenameRemediation\Notifications'
Assert-Equal ($global:RenameTestFixture.Registry[$notificationKey].ContainsKey('User_S-1-12-1-111-222-333-444')) $true 'First run persists notification history'
Assert-Equal $global:RenameTestFixture.Tasks[0].Principal.UserId 'S-1-12-1-111-222-333-444' 'Task uses actual user SID'
Assert-Equal $global:RenameTestFixture.Tasks[0].Principal.LogonType 'Interactive' 'Task needs interactive logon, no password'
Assert-Equal $global:RenameTestFixture.Tasks[0].Principal.RunLevel 'Limited' 'Task is not elevated'
Assert-Equal $global:RenameTestFixture.Tasks[0].Trigger.Once $true 'Only one scheduled trigger'
Assert-Equal $global:RenameTestFixture.Tasks[0].Settings.DeleteExpiredTaskAfter.TotalHours 1.0 'Expired task cleanup configured'
Assert-Equal ($global:RenameTestFixture.Tasks[0].Action.Argument -like '*-Mode Show') $true 'Task displays toast instead of restarting'

Reset-Fixture
$global:RenameTestFixture.Configured = 'JDOE-LT-AA'
[DeviceNaming.SessionDiscovery]::Sessions = @()
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'Pending with no session still blocked'
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 0 'No task without an interactive user'

Reset-Fixture
$global:RenameTestFixture.Configured = 'JDOE-LT-AA'
[DeviceNaming.SessionDiscovery]::Fail = $true
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'Task registration failure still blocks rename'
Assert-Equal $r.Code 0 'Task failure does not corrupt requirement exit'

Reset-Fixture
$global:RenameTestFixture.Account = $null
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'No user defers'
Reset-Fixture
$global:RenameTestFixture.Account = 'AzureAD\JohnDoe'
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'Ambiguous account defers'
Reset-Fixture
$global:RenameTestFixture.Domain = $true
$r = Invoke-Subject $requirement
Assert-Equal $r.Output '0' 'AD domain computer excluded'
Reset-Fixture
$global:RenameTestFixture.ReadFailure = $true
$r = Invoke-Subject $requirement
Assert-Equal $r.Code 1 'Read failure exit'
Assert-Equal $r.Output '' 'Read failure never says eligible'
Reset-Fixture
$global:RenameTestFixture.CimFailure = $true
$r = Invoke-Subject $requirement
Assert-Equal $r.Code 1 'CIM failure exit'

Reset-Fixture
$r = Invoke-Subject $installer @{ AuditOnly=$true }
Assert-Equal $r.Code 0 'Audit exit'
Assert-Equal $global:RenameTestFixture.Renames 0 'Audit does not rename'
Assert-Equal $global:RenameTestFixture.Registry.Count 0 'Audit does not write state'
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 0 'Audit does not prompt'

Reset-Fixture
$r = Invoke-Subject $installer
Assert-Equal $r.Code 3010 'Successful install needs restart'
Assert-Equal $global:RenameTestFixture.Renames 1 'Rename occurs once'
Assert-Equal ([DeviceNaming.SessionDiscovery]::Calls) 1 'New rename queues toast task'
$r = Invoke-Subject $detection
Assert-Equal $r.Code 0 'Detected before reboot'
Assert-Equal ($r.Output -like 'Rename applied: JDOE-LT-??') $true 'Detection has success output'
$r = Invoke-Subject $installer
Assert-Equal $r.Code 1618 'Rerun defers while pending'
Assert-Equal $global:RenameTestFixture.Renames 1 'Rerun never rerandomizes pending name'
$global:RenameTestFixture.Active = $global:RenameTestFixture.Configured
$r = Invoke-Subject $detection
Assert-Equal $r.Code 0 'Detected after simulated reboot'
$global:RenameTestFixture.Configured = 'SOMEONE-ELSE'
$r = Invoke-Subject $detection
Assert-Equal $r.Code 1 'Stale receipt cannot mask another pending target'

Reset-Fixture
$global:RenameTestFixture.RenameFailure = $true
$r = Invoke-Subject $installer
Assert-Equal $r.Code 1 'Rename failure reaches Intune'
Assert-Equal $global:RenameTestFixture.Registry.Count 0 'Failed rename has no receipt'
Reset-Fixture
$global:RenameTestFixture.WrongPostState = $true
$r = Invoke-Subject $installer
Assert-Equal $r.Code 1 'Unexpected post-state fails'
Assert-Equal $global:RenameTestFixture.Registry.Count 0 'Unverified rename has no receipt'

Reset-Fixture
$global:RenameTestFixture.Chassis = @(18, 10)
$system = Get-CimInstance Win32_ComputerSystem
Assert-Equal (Get-ComputerChassisType $system) 'LT' 'Array classification finds laptop'
$global:RenameTestFixture.Chassis = @(18, 21)
Assert-Equal (Get-ComputerChassisType $system) 'PC' 'Expansion/peripheral is not laptop'
$global:RenameTestFixture.Role = 2
Assert-Equal (Get-ComputerChassisType (Get-CimInstance Win32_ComputerSystem)) 'SRV' 'Standalone server role'

Microsoft.PowerShell.Management\Remove-Item -LiteralPath $testDirectory -Recurse -Force
Write-Output "PASS: $script:Passed checks. Windows APIs and endpoint operations were mocked; validate Windows/SYSTEM behavior in a pilot."
