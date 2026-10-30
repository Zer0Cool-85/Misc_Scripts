<#
Mock-based logic checks plus PowerShell parser validation. No NinjaOne account or
Windows repair commands are used. Functions are loaded without the entrypoint.
These checks do not replace a Windows 11 / NinjaOne pilot. Run with PowerShell 7
or Windows PowerShell 5.1: .\Tests\Test-PackLogic.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Sources = @{}
$script:ScriptRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Scripts'
function Assert-Equal($Actual, $Expected) {
    if ($Actual -ne $Expected) { throw "Expected '$Expected'; got '$Actual'." }
}
function Assert-True($Actual) { if (-not $Actual) { throw 'Expected true.' } }
function Assert-Throws([scriptblock]$Body) {
    $didThrow = $false
    try { & $Body } catch { $didThrow = $true }
    if (-not $didThrow) { throw 'Expected an exception.' }
}
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:Passed++; Write-Output "PASS $Name" }
    catch { $script:Failed++; Write-Output "FAIL $Name -- $($_.Exception.Message) [$($_.ScriptStackTrace)]" }
}
$Load = {
    param([string]$Number)
    . ([scriptblock]::Create($script:Sources[$Number]))
}

foreach ($file in Get-ChildItem -LiteralPath $script:ScriptRoot -Filter '*.ps1') {
    $tokens=$null; $parseErrors=$null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw "Parse errors in $($file.Name): $($parseErrors.Message -join '; ')" }
    $number = $file.Name.Substring(3,2)
    $script:Sources[$number] = (Get-Content -LiteralPath $file.FullName -Raw) -split '# N1_ENTRYPOINT',2 | Select-Object -First 1
    Write-Output "PARSE OK $($file.Name)"
}
if ($script:Sources.Count -ne 10) { throw 'Expected exactly ten scripts.' }

Test-Case 'Default mode is Detect and fields are distinct' {
    $seen=@()
    foreach($num in $script:Sources.Keys) {
        . $Load $num
        Assert-Equal $Mode 'Detect'
        Assert-True ($StatusField -notin $seen)
        Assert-Equal $DetailsField ($StatusField+'Details')
        $seen += $StatusField
    }
}
Test-Case 'Exit-code contract covers every state' {
    . $Load '01'
    foreach($state in @('Healthy','Remediated','NotApplicable')) { Assert-Equal (Get-N1ExitCode $state) 0 }
    Assert-Equal (Get-N1ExitCode Issue) 1
    Assert-Equal (Get-N1ExitCode Error) 2
}
Test-Case 'Detect never invokes repair' {
    . $Load '03'
    function Get-N1Assessment { New-N1Result Issue 'stopped' }
    function Invoke-N1Repair { throw 'REPAIR MUST NOT RUN' }
    Assert-Equal (Invoke-N1Workflow).State Issue
}
Test-Case 'Healthy is not repaired in remediation mode' {
    . $Load '03'; $Mode='Remediate'
    function Get-N1Assessment { New-N1Result Healthy 'running' }
    function Invoke-N1Repair { throw 'REPAIR MUST NOT RUN' }
    Assert-Equal (Invoke-N1Workflow).State Healthy
}
Test-Case 'Successful repair is verified before Remediated' {
    . $Load '03'; $Mode='Remediate'; $script:Checks=0
    function Get-N1Assessment { $script:Checks++; if($script:Checks -eq 1){New-N1Result Issue 'stopped'}else{New-N1Result Healthy 'running'} }
    function Invoke-N1Repair { New-N1Action $true 'started' }
    Assert-Equal (Invoke-N1Workflow).State Remediated
    Assert-Equal $script:Checks 2
}
Test-Case 'Unresolved post-repair issue never turns green' {
    . $Load '02'; $Mode='Remediate'
    function Get-N1Assessment { New-N1Result Issue 'still low' }
    function Invoke-N1Repair { New-N1Action $true 'cleanup attempted' }
    Assert-Equal (Invoke-N1Workflow).State Issue
}
Test-Case 'Refused repair remains an Issue' {
    . $Load '06'; $Mode='Remediate'
    function Get-N1Assessment { New-N1Result Issue 'suspended' }
    Assert-Equal (Invoke-N1Workflow).State Issue
}
Test-Case 'Field publishing writes details then status' {
    . $Load '01'; $script:Writes=@()
    function Set-N1Field { param($Name,$Value,$Type); $script:Writes += $Name }
    Publish-N1Result (New-N1Result Healthy 'ok') 'checked'
    Assert-Equal ($script:Writes -join ',') 'n1RebootStatusDetails,n1RebootStatus'
}
Test-Case 'Failed detail write prevents a Healthy status write' {
    . $Load '01'; $script:Writes=@()
    function Set-N1Field { param($Name,$Value,$Type); $script:Writes += $Name; throw 'denied' }
    Assert-Throws { Publish-N1Result (New-N1Result Healthy 'ok') 'checked' }
    Assert-Equal ($script:Writes -join ',') 'n1RebootStatusDetails'
}
Test-Case 'StatusOnly uses just the status field' {
    . $Load '01'; $StatusOnly=$true; $script:Writes=@()
    function Set-N1Field { param($Name,$Value,$Type); $script:Writes += $Name }
    Publish-N1Result (New-N1Result Healthy 'ok') 'checked'
    Assert-Equal ($script:Writes -join ',') 'n1RebootStatus'
}
Test-Case 'SkipCustomFields makes no field writes' {
    . $Load '01'; $SkipCustomFields=$true
    function Set-N1Field { throw 'WRITE MUST NOT RUN' }
    Publish-N1Result (New-N1Result Healthy 'ok') 'checked'
}
Test-Case 'Modern field command is used and stale native code cleared' {
    . $Load '01'; $global:LASTEXITCODE=99; $script:Used=''
    function Set-NinjaProperty { [CmdletBinding()]param($Name,$Value,$Type,[switch]$Force); $script:Used="$Name/$Value/$Type" }
    Set-N1Field testStatus Healthy Text
    Assert-Equal $script:Used 'testStatus/Healthy/Text'
}
Test-Case 'Legacy field command fallback' {
    . $Load '01'; $script:Used=''
    function Get-N1FieldWriter { 'Ninja-Property-Set' }
    function Ninja-Property-Set { [CmdletBinding()]param($Name,$Value); $script:Used="$Name/$Value" }
    Set-N1Field testStatus Issue Text
    Assert-Equal $script:Used 'testStatus/Issue'
}
Test-Case 'Native field failure is not silently accepted' {
    . $Load '01'
    function Get-N1FieldWriter { 'Ninja-Property-Set' }
    function Ninja-Property-Set { [CmdletBinding()]param($Name,$Value); $global:LASTEXITCODE=5 }
    Assert-Throws { Set-N1Field testStatus Healthy Text }
}

Test-Case 'Reboot healthy below threshold without signals' {
    . $Load '01'
    function Get-CimInstance { [CmdletBinding()]param($ClassName); [pscustomobject]@{LastBootUpTime=(Get-Date).AddDays(-2)} }
    function Test-Path { [CmdletBinding()]param($LiteralPath); $false }
    function Get-N1OptionalRegistryValue { $null }
    Assert-Equal (Get-N1Assessment).State Healthy
}
Test-Case 'Reboot high uptime needs attention' {
    . $Load '01'
    function Get-CimInstance { [CmdletBinding()]param($ClassName); [pscustomobject]@{LastBootUpTime=(Get-Date).AddDays(-20)} }
    function Test-Path { [CmdletBinding()]param($LiteralPath); $false }
    function Get-N1OptionalRegistryValue { $null }
    Assert-Equal (Get-N1Assessment).State Issue
}
Test-Case 'Reboot registry pending signal needs attention' {
    . $Load '01'
    function Get-CimInstance { [CmdletBinding()]param($ClassName); [pscustomobject]@{LastBootUpTime=(Get-Date).AddDays(-1)} }
    function Test-Path { [CmdletBinding()]param($LiteralPath); $LiteralPath -like '*RebootRequired' }
    function Get-N1OptionalRegistryValue { $null }
    Assert-Equal (Get-N1Assessment).State Issue
}
Test-Case 'File rename reboot hint is optional' {
    . $Load '01'
    function Get-CimInstance { [CmdletBinding()]param($ClassName); [pscustomobject]@{LastBootUpTime=(Get-Date).AddDays(-1)} }
    function Test-Path { [CmdletBinding()]param($LiteralPath); $false }
    function Get-N1OptionalRegistryValue { 'test-pending-file' }
    Assert-Equal (Get-N1Assessment).State Healthy
    $IncludePendingFileRename=$true
    Assert-Equal (Get-N1Assessment).State Issue
}
Test-Case 'Reboot repair never restarts a device' {
    . $Load '01'
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Disk GB and percentage thresholds are both enforced' {
    . $Load '02'; $script:Free=20GB; $script:Size=100GB
    function Get-N1SystemDisk { [pscustomobject]@{Size=$script:Size;FreeSpace=$script:Free} }
    Assert-Equal (Get-N1Assessment).State Healthy
    $script:Free=14GB
    Assert-Equal (Get-N1Assessment).State Issue
    $script:Free=20GB; $script:Size=1000GB
    Assert-Equal (Get-N1Assessment).State Issue
}
Test-Case 'Disk cleanup refuses a reparse root' {
    . $Load '02'; $oldRoot=$env:SystemRoot; $env:SystemRoot=[IO.Path]::GetTempPath()
    function Get-Item { [CmdletBinding()]param($LiteralPath,[switch]$Force); [pscustomobject]@{PSIsContainer=$true;Attributes=[IO.FileAttributes]::ReparsePoint} }
    try { Assert-Throws { Invoke-N1Repair } } finally { $env:SystemRoot=$oldRoot }
}
Test-Case 'Disk cleanup deletes only aged top-level files and respects size limit' {
    . $Load '02'; $oldRoot=$env:SystemRoot; $env:SystemRoot=[IO.Path]::GetTempPath(); $MaxDeleteMB=1
    $script:Deleted=@(); $old=[DateTime]::UtcNow.AddDays(-10); $recent=[DateTime]::UtcNow
    $script:Candidates=@(
        [pscustomobject]@{FullName='old.tmp';PSIsContainer=$false;Attributes=0;LastWriteTimeUtc=$old;CreationTimeUtc=$old;Length=100},
        [pscustomobject]@{FullName='new.tmp';PSIsContainer=$false;Attributes=0;LastWriteTimeUtc=$recent;CreationTimeUtc=$old;Length=100},
        [pscustomobject]@{FullName='link.tmp';PSIsContainer=$false;Attributes=[IO.FileAttributes]::ReparsePoint;LastWriteTimeUtc=$old;CreationTimeUtc=$old;Length=100},
        [pscustomobject]@{FullName='large.tmp';PSIsContainer=$false;Attributes=0;LastWriteTimeUtc=$old;CreationTimeUtc=$old;Length=2MB}
    )
    function Get-N1SystemDisk { [pscustomobject]@{FreeSpace=1GB;Size=100GB} }
    function Get-Item { [CmdletBinding()]param($LiteralPath,[switch]$Force); if($LiteralPath -like '*Temp'){[pscustomobject]@{PSIsContainer=$true;Attributes=0}}else{$script:Candidates | Where-Object FullName -eq $LiteralPath} }
    function Get-ChildItem { [CmdletBinding()]param($LiteralPath,[switch]$File,[switch]$Force); $script:Candidates }
    function Remove-Item { [CmdletBinding()]param($LiteralPath,[switch]$Force); $script:Deleted += $LiteralPath }
    try { $null=Invoke-N1Repair; Assert-Equal ($script:Deleted -join ',') 'old.tmp' } finally { $env:SystemRoot=$oldRoot }
}
Test-Case 'IME missing is an Issue and is not reinstalled' {
    . $Load '03'; function Get-N1Service { $null }
    Assert-Equal (Get-N1Assessment).State Issue
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'IME disabled is an Issue and startup policy is preserved' {
    . $Load '03'; function Get-N1Service { [pscustomobject]@{State='Stopped';StartMode='Disabled';Name='IntuneManagementExtension'} }
    Assert-Equal (Get-N1Assessment).State Issue
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'IME running is Healthy' {
    . $Load '03'; function Get-N1Service { [pscustomobject]@{State='Running';StartMode='Auto';Name='IntuneManagementExtension'} }
    Assert-Equal (Get-N1Assessment).State Healthy
}
Test-Case 'Required service names are deduplicated and reject filter injection' {
    . $Load '04'; $ServiceNamesCsv=' svc1,svc1, svc2 '
    Assert-Equal (@(Get-N1RequiredNames) -join ',') 'svc1,svc2'
    $ServiceNamesCsv="bad'name"
    Assert-Throws { Get-N1RequiredNames }
}
Test-Case 'Required services do not start without explicit option' {
    . $Load '04'
    function Start-N1ExistingService { throw 'START MUST NOT RUN' }
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Required service repair starts only existing nondisabled stopped service' {
    . $Load '04'; $AllowServiceStart=$true; $ServiceNamesCsv='missing,disabled,stopped,running'; $script:Started=@()
    function Get-N1Service { param($Name); switch($Name){ 'missing'{$null};'disabled'{[pscustomobject]@{State='Stopped';StartMode='Disabled'}};'stopped'{[pscustomobject]@{State='Stopped';StartMode='Auto'}};'running'{[pscustomobject]@{State='Running';StartMode='Auto'}} } }
    function Start-N1ExistingService { param($Name); $script:Started += $Name }
    Assert-Equal (Invoke-N1Repair).Attempted $true
    Assert-Equal ($script:Started -join ',') 'stopped'
}
Test-Case 'Required service start failure remains Issue after verification' {
    . $Load '04'; $Mode='Remediate'; $AllowServiceStart=$true
    function Get-N1Service { [pscustomobject]@{Name='CSFalconService';State='Stopped';StartMode='Auto'} }
    function Start-N1ExistingService { throw 'tamper protected' }
    Assert-Equal (Invoke-N1Workflow).State Issue
}
Test-Case 'Firewall requires every effective profile enabled' {
    . $Load '05'; $script:PublicEnabled='False'
    function Get-NetFirewallProfile { [CmdletBinding()]param($PolicyStore); foreach($n in @('Domain','Private','Public')){[pscustomobject]@{Name=$n;Enabled=$(if($n -eq 'Public'){$script:PublicEnabled}else{'True'})}} }
    Assert-Equal (Get-N1Assessment).State Issue
    $script:PublicEnabled='True'; Assert-Equal (Get-N1Assessment).State Healthy
}
Test-Case 'Firewall no-change default even in Remediate mode' {
    . $Load '05'; Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Firewall verification catches overriding central policy' {
    . $Load '05'; $Mode='Remediate'; $AllowEnableFirewall=$true; $script:Stores=@()
    function Get-NetFirewallProfile { [CmdletBinding()]param($PolicyStore); foreach($n in @('Domain','Private','Public')){[pscustomobject]@{Name=$n;Enabled='False'}} }
    function Set-NetFirewallProfile { [CmdletBinding()]param($Name,$Enabled,$PolicyStore); $script:Stores += $PolicyStore }
    Assert-Equal (Invoke-N1Workflow).State Issue
    Assert-Equal ($script:Stores | Select-Object -Unique) PersistentStore
}
Test-Case 'BitLocker encrypted protected volume is Healthy' {
    . $Load '06'
    function Get-N1OSBitLocker { [pscustomobject]@{VolumeStatus='FullyEncrypted';ProtectionStatus='On';EncryptionPercentage=100;LockStatus='Unlocked'} }
    Assert-Equal (Get-N1Assessment).State Healthy
}
Test-Case 'BitLocker suspension does not resume without explicit option' {
    . $Load '06'; Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'BitLocker unencrypted/paused/locked states cannot be resumed' {
    . $Load '06'; $AllowResumeBitLocker=$true
    function Resume-BitLocker { throw 'RESUME MUST NOT RUN' }
    function Get-N1OSBitLocker { [pscustomobject]@{VolumeStatus=$script:Volume;ProtectionStatus='Off';LockStatus=$script:Lock} }
    foreach($v in @('FullyDecrypted','EncryptionInProgress','EncryptionPaused','DecryptionInProgress')) {
        $script:Volume=$v; $script:Lock='Unlocked'; Assert-Equal (Invoke-N1Repair).Attempted $false
    }
    $script:Volume='FullyEncrypted'; $script:Lock='Locked'; Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'BitLocker eligible suspension can be resumed with explicit option' {
    . $Load '06'; $AllowResumeBitLocker=$true; $script:Resumed=$false
    function Get-N1OSBitLocker { [pscustomobject]@{VolumeStatus='FullyEncrypted';ProtectionStatus='Off';LockStatus='Unlocked'} }
    function Resume-BitLocker { [CmdletBinding()]param($MountPoint); $script:Resumed=$true }
    Assert-Equal (Invoke-N1Repair).Attempted $true
    Assert-True $script:Resumed
}
Test-Case 'Time numeric parsing supports translated labels and rejects malformed output' {
    . $Load '07'
    $s=ConvertFrom-N1TimeStatus "Indicateur: 0 (aucun)`nStrate: 3 (secondaire)"
    Assert-Equal $s.Leap 0; Assert-Equal $s.Stratum 3
    Assert-Throws { ConvertFrom-N1TimeStatus 'unrecognized' }
    Assert-Throws { ConvertFrom-N1TimeStatus "Leap: 99`nStratum: 3" }
}
Test-Case 'Time unsynchronized leap is an Issue' {
    . $Load '07'; $oldRoot=$env:SystemRoot; $env:SystemRoot=[IO.Path]::GetTempPath()
    function Get-N1Service { [pscustomobject]@{State='Running';StartMode='Manual'} }
    function Invoke-N1Native { [pscustomobject]@{ExitCode=0;Output="Leap Indicator: 3`nStratum: 0"} }
    try { Assert-Equal (Get-N1Assessment).State Issue } finally { $env:SystemRoot=$oldRoot }
}
Test-Case 'Time synchronized report is Healthy' {
    . $Load '07'; $oldRoot=$env:SystemRoot; $env:SystemRoot=[IO.Path]::GetTempPath()
    function Get-N1Service { [pscustomobject]@{State='Running';StartMode='Manual'} }
    function Invoke-N1Native { [pscustomobject]@{ExitCode=0;Output="Leap Indicator: 0`nStratum: 3"} }
    try { Assert-Equal (Get-N1Assessment).State Healthy } finally { $env:SystemRoot=$oldRoot }
}
Test-Case 'Time disabled service is not force enabled' {
    . $Load '07'; function Get-N1Service { [pscustomobject]@{State='Stopped';StartMode='Disabled'} }
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Fast Startup central require-on policy is left unchanged' {
    . $Load '08'
    function Get-N1OptionalRegistryValue { param($Path,$Name); if($Path -like '*Policies*'){1}else{0} }
    Assert-Equal (Get-N1Assessment).State Issue
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Fast Startup missing local value is not assumed compliant' {
    . $Load '08'; function Get-N1OptionalRegistryValue { $null }
    Assert-Equal (Get-N1Assessment).State Issue
}
Test-Case 'Fast Startup explicit zero is Healthy' {
    . $Load '08'; function Get-N1OptionalRegistryValue { 0 }
    Assert-Equal (Get-N1Assessment).State Healthy
}
Test-Case 'Image Quick and Full choose correct DISM detection switches' {
    . $Load '09'; $script:ImageCalls=@()
    function Repair-WindowsImage { [CmdletBinding()]param([switch]$Online,[switch]$CheckHealth,[switch]$ScanHealth,[switch]$NoRestart); $script:ImageCalls += "Quick=$CheckHealth Full=$ScanHealth"; [pscustomobject]@{ImageHealthState='Healthy';RestartNeeded=$false} }
    Assert-Equal (Get-N1Assessment).State Healthy
    $ScanType='Full'; Assert-Equal (Get-N1Assessment).State Healthy
    Assert-Equal ($script:ImageCalls -join ';') 'Quick=True Full=False;Quick=False Full=True'
}
Test-Case 'Image repairable flag is Issue and requires explicit repair option' {
    . $Load '09'
    function Repair-WindowsImage { [CmdletBinding()]param([switch]$Online,[switch]$CheckHealth,[switch]$NoRestart); [pscustomobject]@{ImageHealthState='Repairable';RestartNeeded=$false} }
    Assert-Equal (Get-N1Assessment).State Issue
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Image nonrepairable is not sent through RestoreHealth' {
    . $Load '09'; $AllowOnlineRepair=$true
    function Repair-WindowsImage { [CmdletBinding()]param([switch]$Online,[switch]$CheckHealth,[switch]$NoRestart); [pscustomobject]@{ImageHealthState='NonRepairable';RestartNeeded=$false} }
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Image unknown health object fails closed' {
    . $Load '09'
    function Repair-WindowsImage { [CmdletBinding()]param([switch]$Online,[switch]$CheckHealth,[switch]$NoRestart); [pscustomobject]@{ImageHealthState='Unexpected';RestartNeeded=$false} }
    Assert-Throws { Get-N1Assessment }
}
Test-Case 'Local admin flags unexpected direct members by SID' {
    . $Load '10'
    function Get-LocalUser { [CmdletBinding()]param(); [pscustomobject]@{SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-500'}} }
    function Get-LocalGroupMember { [CmdletBinding()]param($SID); [pscustomobject]@{Name='PC\Admin';SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-500'}}; [pscustomobject]@{Name='AzureAD\ApprovedUser';SID=[pscustomobject]@{Value='S-1-12-1-1-2-3-4'}} }
    Assert-Equal (Get-N1Assessment).State Issue
    $AllowedSidsCsv='S-1-12-1-1-2-3-4'; Assert-Equal (Get-N1Assessment).State Healthy
    Assert-Equal (Invoke-N1Repair).Attempted $false
}
Test-Case 'Local admin enumeration failures do not become Healthy' {
    . $Load '10'
    function Get-LocalUser { [CmdletBinding()]param(); [pscustomobject]@{SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-500'}} }
    function Get-LocalGroupMember { [CmdletBinding()]param($SID); throw 'unresolved member' }
    Assert-Throws { Get-N1Assessment }
}

Write-Output "RESULT: $script:Passed passed; $script:Failed failed; 10 scripts parsed."
if ($script:Failed) { exit 1 }
exit 0
