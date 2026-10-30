<#
.SYNOPSIS
Required services with NinjaOne device custom-field reporting.
.DESCRIPTION
NinjaOne Remediation Starter Pack 1.0.0. Windows x64 workstations, PowerShell 5.1+.
Default is Detect. Each file is standalone; paste/import this entire file.
Exit 0: Healthy/Remediated/NotApplicable; 1: Issue; 2: Error.
Create n1ServicesStatus (Text) and n1ServicesStatusDetails (Multi-line), with Automation Read/Write.
See README.md for scope, safeguards, parameters, conditions, and validation limitations.
.EXAMPLE
.\N1-04-RequiredServices.ps1 -Mode Detect -ServiceNamesCsv "CSFalconService" -SkipCustomFields
#>
[CmdletBinding()]
param(
    [ValidateSet('Detect','Remediate')][string]$Mode = 'Detect',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$StatusField = 'n1ServicesStatus',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$DetailsField = 'n1ServicesStatusDetails',
    [switch]$StatusOnly,
    [switch]$SkipCustomFields,
    [ValidateNotNullOrEmpty()][string]$ServiceNamesCsv = 'CSFalconService',
    [switch]$AllowServiceStart
)
$script:CheckId = 'RequiredServices'

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:PackVersion = '1.0.0'

function New-N1Result {
    param([ValidateSet('Healthy','Remediated','Issue','Error','NotApplicable')][string]$State,
          [string]$Summary, [string]$Evidence = '')
    [pscustomobject]@{ State = $State; Summary = $Summary; Evidence = $Evidence }
}
function New-N1Action {
    param([bool]$Attempted, [string]$Summary)
    [pscustomobject]@{ Attempted = $Attempted; Summary = $Summary }
}
function Get-N1OptionalRegistryValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $null }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    try { return $key.GetValue($Name, $null) } finally { $key.Close() }
}
function Assert-N1Environment {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This script requires Windows.' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'PowerShell 5.1 or later is required.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Select 64-bit architecture in NinjaOne.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run as SYSTEM in NinjaOne, or elevated for a local pilot.'
    }
    $script:OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
}
function Get-N1FieldWriter {
    if (Get-Command Set-NinjaProperty -ErrorAction SilentlyContinue) { return 'Set-NinjaProperty' }
    if (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue) { return 'Ninja-Property-Set' }
    throw 'NinjaOne field commands are unavailable. Run through the NinjaOne agent; for local testing only use -SkipCustomFields.'
}
function Set-N1Field {
    param([string]$Name, [string]$Value, [ValidateSet('Text','MultiLine')][string]$Type)
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'A custom field name is empty.' }
    $writer = Get-N1FieldWriter
    # Older wrappers can leave errors in LASTEXITCODE instead of throwing.
    $global:LASTEXITCODE = 0
    if ($writer -eq 'Set-NinjaProperty') {
        $null = Set-NinjaProperty -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
    } else {
        $null = Ninja-Property-Set -Name $Name -Value $Value -ErrorAction Stop
    }
    if ($global:LASTEXITCODE -ne 0) { throw "Custom field '$Name' write returned $global:LASTEXITCODE." }
}
function Publish-N1Result {
    param($Result, [string]$Detail)
    if ($SkipCustomFields) { return }
    # Publish the status last. A failed detail write must not produce a fresh green status.
    if (-not $StatusOnly) { Set-N1Field -Name $DetailsField -Value $Detail -Type MultiLine }
    Set-N1Field -Name $StatusField -Value $Result.State -Type Text
}
function Get-N1ExitCode {
    param([string]$State)
    if ($State -eq 'Error') { return 2 }
    if ($State -eq 'Issue') { return 1 }
    return 0
}
function Invoke-N1Native {
    param([string]$FilePath, [string]$Arguments, [int]$TimeoutSeconds = 45)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $FilePath
    $p.StartInfo.Arguments = $Arguments
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.CreateNoWindow = $true
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    try {
        if (-not $p.Start()) { throw "Unable to start $FilePath" }
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch { }
            throw "Native command timed out after $TimeoutSeconds seconds: $FilePath $Arguments"
        }
        $out = $outTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()
        [pscustomobject]@{ ExitCode = $p.ExitCode; Output = ($out + "`n" + $err).Trim() }
    } finally { $p.Dispose() }
}
function Get-N1Service {
    param([string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9_. -]+$') { throw "Invalid service name: $Name" }
    Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
}
function Start-N1ExistingService {
    param([string]$Name)
    $svc = Get-N1Service -Name $Name
    if ($null -eq $svc) { throw "Service '$Name' is missing; installation requires separate handling." }
    if ($svc.StartMode -eq 'Disabled') { throw "Service '$Name' is disabled; startup policy was left unchanged." }
    if ($svc.State -eq 'Running') { return }
    if ($svc.State -notin @('Stopped','Start Pending')) { throw "Service '$Name' is $($svc.State); automatic restart is not permitted." }
    if ($svc.State -eq 'Stopped') { Start-Service -Name $Name -ErrorAction Stop }
    $controller = Get-Service -Name $Name -ErrorAction Stop
    $controller.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
}
function Invoke-N1Workflow {
    $before = Get-N1Assessment
    if ($before.State -ne 'Issue' -or $Mode -ne 'Remediate') { return $before }
    $action = Invoke-N1Repair -Before $before
    if (-not $action.Attempted) {
        $before.Evidence += "`nRepair decision: $($action.Summary)"
        return $before
    }
    $after = Get-N1Assessment
    if ($after.State -eq 'Healthy') { $after.State = 'Remediated' }
    $after.Evidence = "Before: $($before.Summary)`nAction: $($action.Summary)`nAfter: $($after.Evidence)"
    return $after
}

function Get-N1RequiredNames {
    $names = @($ServiceNamesCsv.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($names.Count -eq 0 -or $names.Count -gt 20) { throw 'Specify between 1 and 20 service names.' }
    foreach ($name in $names) { if ($name -notmatch '^[A-Za-z0-9_. -]+$') { throw "Invalid service name: $name" } }
    $names
}
function Get-N1Assessment {
    $issues = @(); $lines = @()
    foreach ($name in @(Get-N1RequiredNames)) {
        $svc = Get-N1Service $name
        if ($null -eq $svc) { $issues += "$name missing"; $lines += "$name | Missing"; continue }
        $lines += "$name | $($svc.State) | StartMode=$($svc.StartMode)"
        if ($svc.State -ne 'Running' -or $svc.StartMode -eq 'Disabled') { $issues += "$name $($svc.State)/$($svc.StartMode)" }
    }
    if ($issues.Count) { return New-N1Result Issue ($issues -join '; ') ($lines -join "`n") }
    New-N1Result Healthy 'All configured required services are running.' (($lines -join "`n") + "`nProcess/service presence does not prove agent cloud connectivity or product health.")
}
function Invoke-N1Repair {
    param($Before)
    if (-not $AllowServiceStart) { return New-N1Action $false 'Add -AllowServiceStart only for services you have approved for automatic starting.' }
    $actions = @(); $attempted = $false
    foreach ($name in @(Get-N1RequiredNames)) {
        $svc = Get-N1Service $name
        if ($null -eq $svc) { $actions += "$name missing; installation needed"; continue }
        if ($svc.StartMode -eq 'Disabled') { $actions += "$name disabled; policy review needed"; continue }
        if ($svc.State -eq 'Running') { continue }
        $attempted = $true
        try { Start-N1ExistingService $name; $actions += "$name started" }
        catch { $actions += "$name start failed: $($_.Exception.Message)" }
    }
    New-N1Action $attempted ($actions -join '; ')
}

# N1_ENTRYPOINT -- validation harness loads definitions above this marker only.
$mutex = $null
$lockHeld = $false
$publishAllowed = $true
$result = $null
try {
    Assert-N1Environment
    $mutex = New-Object System.Threading.Mutex($false, ('Global\N1RP_' + $script:CheckId))
    try { $lockHeld = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $lockHeld = $true }
    if (-not $lockHeld) {
        $publishAllowed = $false
        throw 'This check is already running. No changes or field writes were made by this overlapping run.'
    }
    if (-not $SkipCustomFields) { $null = Get-N1FieldWriter }
    if ([int]$script:OperatingSystem.ProductType -ne 1) {
        $result = New-N1Result NotApplicable 'Workstation scope only; Windows Server is excluded.'
    } else {
        $result = Invoke-N1Workflow
    }
} catch {
    $result = New-N1Result Error 'The check or repair could not complete.' $_.Exception.Message
}
try {
    $checkedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $detail = "Check: $script:CheckId`nVersion: $script:PackVersion`nState: $($result.State)`nCheckedUtc: $checkedUtc`nMode: $Mode`nSummary: $($result.Summary)`n$($result.Evidence)"
    if ($detail.Length -gt 9000) { $detail = $detail.Substring(0,8950) + "`n[Details truncated]" }
    if ($publishAllowed) {
        try { Publish-N1Result -Result $result -Detail $detail }
        catch {
            $fieldError = $_.Exception.Message
            $result = New-N1Result Error 'Custom-field reporting failed; device field values may be stale.' $fieldError
            $detail += "`nReporting error: $fieldError"
            if (-not $SkipCustomFields) {
                try { Set-N1Field -Name $StatusField -Value Error -Type Text } catch { }
            }
        }
    }
    Write-Output "N1_RESULT=$($result.State)"
    Write-Output "N1_CHECK=$script:CheckId"
    Write-Output "N1_CHECKED_UTC=$checkedUtc"
    Write-Output "N1_SUMMARY=$($result.Summary)"
    Write-Output $detail
    $exitCode = Get-N1ExitCode -State $result.State
} finally {
    if ($lockHeld -and $null -ne $mutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $exitCode
