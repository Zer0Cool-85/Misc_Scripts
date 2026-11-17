#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PolicyEngine.psm1') -Force -DisableNameChecking
$lock=$null; $root=$null; $mutating=$false; $oldTask=$null; $service=$null
$oldFiles=@{}; $beforeValues=@(); $beforeAudit=$null; $hadInstallation=$false
$transactionFiles=@('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1','PackageManifest.json','State.json','Status.json')
try {
    Assert-Administrator
    $manifest=Read-PackageManifest $PSScriptRoot
    $config=Read-PolicyConfiguration (Join-Path $PSScriptRoot 'PolicyConfig.json')
    if ($manifest.ConfigurationId -cne $config.ConfigurationId) {throw 'Package must be regenerated with Prepare-Package.ps1.'}
    $root=Get-ManagerRoot
    Initialize-PrivateRoot $root
    $lock=Enter-ManagerLock $root
    $hadInstallation=Test-Path -LiteralPath (Join-Path $root 'PackageManifest.json')
    if ($hadInstallation -and -not (Test-Path -LiteralPath (Join-Path $root 'State.json'))) {throw 'Existing manager state is missing; recover its backup before replacing it.'}
    foreach ($name in $transactionFiles) {
        $path=Join-Path $root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $oldFiles[$name]=[IO.File]::ReadAllBytes($path) }
    }
    $service=Connect-TaskService
    $oldTask=Get-ManagerTask $service; Assert-OwnedTask $oldTask
    $oldDefinition=$null; $oldSddl=$null; $oldEnabled=$false
    if ($null -ne $oldTask) { $oldDefinition=$oldTask.Definition; $oldSddl=$oldTask.GetSecurityDescriptor(7); $oldEnabled=$oldTask.Enabled }
    $previous=@()
    if ($hadInstallation) { $previous=@((Read-ManagerState $root).LastDesired) }
    $effective=@(Get-MergedPolicySet $previous @($config.Desired))
    $beforeValues=@($effective | ForEach-Object { Get-RegistrySnapshot $_.Name })
    if ($config.RunOnRegistryChange -or $hadInstallation) { $beforeAudit=Get-AuditSnapshot }
    $mutating=$true
    # Lock FIRST, then suspend the task. The live registry values remain in place.
    if ($null -ne $oldTask) { $oldTask.Enabled=$false; $oldTask.Stop(0) }
    Write-ManagerLog $root "Beginning install/update: $($config.ConfigurationId); existing=$hadInstallation."
    if (-not $hadInstallation) {
        Write-PrivateJson (Join-Path $root 'State.json') ([ordered]@{SchemaVersion=1;Original=@();LastDesired=@()})
    }
    foreach ($name in @('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1','PackageManifest.json')) {
        Write-AtomicBytes (Join-Path $root $name) ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $name)))
    }
    $null=Invoke-PolicyEnforcement $root $config
    if ($config.RunOnRegistryChange) { Ensure-RegistryAuditing $root $config -Install }
    else { Restore-ManagerAudit $root }
    Register-ManagerTask $service $root $config
    Assert-InstallationHealthy $root
    Write-ManagerLog $root "Install/update committed: $($config.ConfigurationId)."
    Write-Output "Claude policy manager installed/updated: $($config.ConfigurationId)."
    $mutating=$false
    exit 0
} catch {
    $failure=$_.Exception.Message
    if ($mutating) {
        try {
            # Remove the new registration before restoring files and policy snapshots.
            $task=Get-ManagerTask $service
            if ($null -ne $task) { $task.Enabled=$false; $task.Stop(0); $service.GetFolder('\').DeleteTask('ClaudePolicyManager-Enforce',0) }
            foreach ($snapshot in $beforeValues) {Set-RegistrySnapshot $snapshot}
            if ($null -ne $beforeAudit) {Set-AuditSnapshot $beforeAudit}
            elseif (Test-Path -LiteralPath (Join-Path $root 'State.json')) {Restore-ManagerAudit $root}
            foreach ($name in $transactionFiles) {
                $path=Join-Path $root $name
                if ($oldFiles.ContainsKey($name)) { Write-AtomicBytes $path $oldFiles[$name] }
                elseif (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
            }
            if ($null -ne $oldDefinition) {
                [void]$service.GetFolder('\').RegisterTaskDefinition('ClaudePolicyManager-Enforce',$oldDefinition,22,'SYSTEM',$null,5,$oldSddl)
                (Get-ManagerTask $service).Enabled=$oldEnabled
            }
            Write-ManagerLog $root "Update failed and prior configuration restored: $failure"
        } catch {
            Write-Error "Rollback also failed: $($_.Exception.Message). Recover the previous package before further changes." -ErrorAction Continue
        }
    }
    Write-Error "Install/update failed: $failure" -ErrorAction Continue
    exit 1
} finally { if ($null -ne $lock) {$lock.Dispose()} }
