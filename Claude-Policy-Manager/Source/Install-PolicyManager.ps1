#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$lock=$null; $root=$null; $mutating=$false; $oldTask=$null; $service=$null
$oldFiles=@{}; $beforeValues=@(); $beforeAudit=$null; $hadInstallation=$false
$transactionFiles=@('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1','PackageManifest.json','State.json','Status.json')
$stage='Loading policy engine'
try {
    Write-Output ("[{0}] Install started; PowerShell={1}; 64BitProcess={2}; OS={3}" -f [DateTime]::UtcNow.ToString('o'),$PSVersionTable.PSVersion,[Environment]::Is64BitProcess,$env:OS)
    Import-Module (Join-Path $PSScriptRoot 'PolicyEngine.psm1') -Force -DisableNameChecking
    $stage='Checking SYSTEM and native process context'
    Assert-Administrator
    $stage='Validating package manifest and payload hashes'
    Write-Output "Stage: $stage"
    $manifest=Read-PackageManifest $PSScriptRoot
    $stage='Validating policy JSON'
    Write-Output "Stage: $stage"
    $config=Read-PolicyConfiguration (Join-Path $PSScriptRoot 'PolicyConfig.json')
    if ($manifest.ConfigurationId -cne $config.ConfigurationId) {throw 'Package must be regenerated with Prepare-Package.ps1.'}
    $root=Get-ManagerRoot
    $stage='Creating or validating secured manager folder'
    Write-Output "Stage: $stage"
    Initialize-PrivateRoot $root
    $stage='Acquiring operation lock'
    Write-Output "Stage: $stage"
    $lock=Enter-ManagerLock $root
    $hadInstallation=Test-Path -LiteralPath (Join-Path $root 'PackageManifest.json')
    if ($hadInstallation -and -not (Test-Path -LiteralPath (Join-Path $root 'State.json'))) {throw 'Existing manager state is missing; recover its backup before replacing it.'}
    foreach ($name in $transactionFiles) {
        $path=Join-Path $root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { $oldFiles[$name]=[IO.File]::ReadAllBytes($path) }
    }
    $stage='Connecting to Task Scheduler and checking existing task'
    Write-Output "Stage: $stage"
    $service=Connect-TaskService
    $oldTask=Get-ManagerTask $service; Assert-OwnedTask $oldTask
    $oldDefinition=$null; $oldSddl=$null; $oldEnabled=$false
    if ($null -ne $oldTask) { $oldDefinition=$oldTask.Definition; $oldSddl=$oldTask.GetSecurityDescriptor(7); $oldEnabled=$oldTask.Enabled }
    $previous=@()
    if ($hadInstallation) { $previous=@((Read-ManagerState $root).LastDesired) }
    $effective=@(Get-MergedPolicySet $previous @($config.Desired))
    $stage='Snapshotting registry policy values'
    Write-Output "Stage: $stage"
    $beforeValues=@($effective | ForEach-Object { Get-RegistrySnapshot $_.Name })
    $stage='Snapshotting registry audit permissions'
    Write-Output "Stage: $stage"
    if ($config.RunOnRegistryChange -or $hadInstallation) { $beforeAudit=Get-AuditSnapshot }
    $stage='Starting protected installation transaction'
    Write-Output "Stage: $stage"
    $mutating=$true
    # Lock FIRST, then suspend the task. The live registry values remain in place.
    if ($null -ne $oldTask) { $oldTask.Enabled=$false; $oldTask.Stop(0) }
    Write-ManagerLog $root "Beginning install/update: $($config.ConfigurationId); existing=$hadInstallation."
    if (-not $hadInstallation) {
        Write-PrivateJson (Join-Path $root 'State.json') ([ordered]@{SchemaVersion=1;Original=@();LastDesired=@()})
    }
    $stage='Copying protected payload'
    Write-Output "Stage: $stage"
    foreach ($name in @('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1','PackageManifest.json')) {
        Write-AtomicBytes (Join-Path $root $name) ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $name)))
    }
    $stage='Applying registry policies'
    Write-Output "Stage: $stage"
    $null=Invoke-PolicyEnforcement $root $config
    $stage='Configuring registry auditing'
    Write-Output "Stage: $stage"
    if ($config.RunOnRegistryChange) { Ensure-RegistryAuditing $root $config -Install }
    else { Restore-ManagerAudit $root }
    $stage='Registering enforcement task'
    Write-Output "Stage: $stage"
    Register-ManagerTask $service $root $config
    $stage='Verifying installed files, permissions, task, auditing and policies'
    Write-Output "Stage: $stage"
    Assert-InstallationHealthy $root
    Write-ManagerLog $root "Install/update committed: $($config.ConfigurationId)."
    Write-Output "Claude policy manager installed/updated: $($config.ConfigurationId)."
    $mutating=$false
    exit 0
} catch {
    $failureRecord=$_
    $failure=$failureRecord.Exception.Message
    Write-Output "INSTALL FAILED during stage: $stage"
    Write-Output ($failureRecord | Format-List * -Force | Out-String -Width 240)
    Write-Output ("Position: {0}" -f $failureRecord.InvocationInfo.PositionMessage)
    Write-Output ("Script stack: {0}" -f $failureRecord.ScriptStackTrace)
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
