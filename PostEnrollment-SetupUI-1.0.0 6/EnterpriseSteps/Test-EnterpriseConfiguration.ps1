#Requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Config/Enterprise-Example.json'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Core/Setup.Common.ps1')
$cfg = Read-SetupConfiguration -Path $ConfigPath -PackageRoot $root
$problems = [Collections.Generic.List[string]]::new()
foreach ($step in $cfg.Steps | Where-Object Enabled) {
    $file = Resolve-SetupContentPath $root $step.Script
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { $problems.Add("$($step.Id): PowerShell parse errors.") }
    $names = @()
    if ($null -ne $ast.ParamBlock) { $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    foreach ($p in $step.Parameters.PSObject.Properties) {
        if ($p.Name -notin $names) { $problems.Add("$($step.Id): Unknown parameter $($p.Name).") }
        if ($p.Name -in @('MsiRelativePath','PackageRelativePath','LicenseRelativePath','OdtRelativePath','DependencyRelativePaths','GetHelpRelativePath','CatalogRelativePath','ChromeMsiRelativePath','DriveExeRelativePath')) {
            foreach ($relative in @($p.Value)) {
                if ($relative) {
                    try {
                        $path = Resolve-SetupContentPath $root $relative
                        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("$($step.Id): Missing payload $relative") }
                    }
                    catch { $problems.Add("$($step.Id): $($_.Exception.Message)") }
                }
            }
        }
    }
    $parameters = $step.Parameters
    if ($step.Script -match 'Step-UpdateOtherApps\.ps1$') {
        if ($step.Required -or 20001 -notin $step.NonBlockingSkipExitCodes) { $problems.Add("$($step.Id): configure Required=false and NonBlockingSkipExitCodes=[20001].") }
        $budget=120
        if (-not $parameters.PSObject.Properties['RunMachineUpdates'] -or $parameters.RunMachineUpdates) { $budget+= $(if ($parameters.PSObject.Properties['MachineTimeoutSeconds']) { $parameters.MachineTimeoutSeconds } else { 900 }) }
        if (-not $parameters.PSObject.Properties['RunUserUpdates'] -or $parameters.RunUserUpdates) { $budget+=90+ $(if ($parameters.PSObject.Properties['UserTimeoutSeconds']) { $parameters.UserTimeoutSeconds } else { 300 }) }
        if ($step.TimeoutSeconds -lt $budget) { $problems.Add("$($step.Id): set the UI timeout to at least $budget seconds so ordinary update timeouts can be skipped.") }
    }
    if ($step.Script -like '*/Step-InstallMsi.ps1') {
        if ($null -eq $parameters.PSObject.Properties['ProductCode'] -or $parameters.ProductCode -eq '{00000000-0000-0000-0000-000000000000}') { $problems.Add("$($step.Id): Set the real MSI ProductCode.") }
    }
    if ($step.Script -match '/Step-Install(CompanyPortal|Notepad)\.ps1$') {
        $mode = 'WinGetThenOffline'
        if ($null -ne $parameters.PSObject.Properties['Mode']) { $mode = $parameters.Mode }
        if ($mode -in @('OfflinePackage','WinGetThenOffline')) {
            if ($null -eq $parameters.PSObject.Properties['PackageRelativePath'] -or -not $parameters.PackageRelativePath) { $problems.Add("$($step.Id): $mode requires a staged PackageRelativePath for offline installation.") }
            $hasLicense = $null -ne $parameters.PSObject.Properties['LicenseRelativePath'] -and -not [string]::IsNullOrWhiteSpace([string]$parameters.LicenseRelativePath)
            $allowUnlicensed = $null -ne $parameters.PSObject.Properties['AllowUnlicensedPackage'] -and $parameters.AllowUnlicensedPackage -is [bool] -and $parameters.AllowUnlicensedPackage
            if (-not $hasLicense -and -not $allowUnlicensed) { $problems.Add("$($step.Id): Supply LicenseRelativePath, or explicitly allow unlicensed provisioning only where the package permits it.") }
        }
        if ($mode -eq 'WinGetThenOffline') {
            foreach ($limit in @(@('WinGetTimeoutSeconds',30,1200), @('WinGetVerifySeconds',0,120))) {
                $property = $parameters.PSObject.Properties[$limit[0]]
                if ($null -ne $property -and ($property.Value -isnot [ValueType] -or $property.Value -is [bool] -or $property.Value -lt $limit[1] -or $property.Value -gt $limit[2] -or [double]$property.Value -ne [Math]::Truncate([double]$property.Value))) { $problems.Add("$($step.Id): $($limit[0]) must be a whole number from $($limit[1]) to $($limit[2]).") }
            }
        }
    }
}
if ($problems.Count) { throw ("Enterprise preflight failed:`r`n" + ($problems -join "`r`n")) }
Write-Host 'PASS: configuration, parameter names and explicitly listed payload paths. This does not validate Windows install behavior, licensing, dependencies, hashes or policy conflicts.'
