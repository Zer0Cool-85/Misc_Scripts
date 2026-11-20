#requires -Version 5.1
# Read-only local probe. The two deployed scripts contain standalone copies of this code.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'Source\Naming.Common.ps1')
$state = Get-ComputerNameState
$decision = Get-RenameEligibility -NameState $state
$upload = Join-Path $root 'Intune\Requirement-RenameComputer.ps1'
[pscustomobject]@{
    NameTrace = Format-RenameNameState -NameState $state
    RunningAs = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    ConsoleAccount = $decision.System.UserName
    ADJoined = $decision.System.PartOfDomain
    RequirementInteger = [int]$decision.Eligible
    Reason = $decision.Reason
    LocalRequirementSHA256 = (Get-FileHash -LiteralPath $upload -Algorithm SHA256).Hash
} | Format-List
