#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('RestoreOriginal','RemoveManaged','KeepPolicies')][string]$Mode='RestoreOriginal')
$ErrorActionPreference='Stop'
$lock=$null; $root=$null; $changed=$false; $service=$null; $task=$null
$before=@(); $beforeAudit=$null; $beforeState=$null
$stage='Loading policy engine'
try {
    Write-Output ("[{0}] Uninstall started; PowerShell={1}; 64BitProcess={2}; OS={3}" -f [DateTime]::UtcNow.ToString('o'),$PSVersionTable.PSVersion,[Environment]::Is64BitProcess,$env:OS)
    Import-Module (Join-Path $PSScriptRoot 'PolicyEngine.psm1') -Force -DisableNameChecking
    $stage='Checking SYSTEM and native process context'
    Assert-Administrator
    $stage='Locating installed manager'
    Write-Output "Stage: $stage"
    $root=Get-ManagerRoot
    if (-not (Test-Path -LiteralPath $root)) { Write-Output 'Manager already absent.'; exit 0 }
    $stage='Checking manager folder'
    Write-Output "Stage: $stage"
    $null=@(Get-SafeTree $root)
    Assert-PrivatePermissions $root
    $stage='Acquiring operation lock'
    Write-Output "Stage: $stage"
    $lock=Enter-ManagerLock $root
    # A delayed uninstall from config A must not remove config B.
    $stage='Checking uninstall package identity'
    Write-Output "Stage: $stage"
    $sourceManifest=Join-Path $PSScriptRoot 'PackageManifest.json'
    $installedManifest=Join-Path $root 'PackageManifest.json'
    if (-not (Test-Path -LiteralPath $sourceManifest) -or -not (Test-Path -LiteralPath $installedManifest)) { throw 'Manifest missing; use the matching prepared package to uninstall.' }
    if ((Get-FileDigest $sourceManifest) -cne (Get-FileDigest $installedManifest)) {
        Write-Output 'Skipped: a different configuration/package is currently installed.'
        exit 0
    }
    $stage='Reading previous managed state'
    Write-Output "Stage: $stage"
    $state=Read-ManagerState $root
    $beforeState=[IO.File]::ReadAllBytes((Join-Path $root 'State.json'))
    $stage='Connecting to Task Scheduler'
    Write-Output "Stage: $stage"
    $service=Connect-TaskService; $task=Get-ManagerTask $service; Assert-OwnedTask $task
    $wasEnabled=$false; $definition=$null; $sddl=$null
    if ($null -ne $task) { $wasEnabled=$task.Enabled; $definition=$task.Definition; $sddl=$task.GetSecurityDescriptor(7) }
    $before=@($state.LastDesired | ForEach-Object {Get-RegistrySnapshot $_.Name})
    $stage='Snapshotting registry audit permissions'
    Write-Output "Stage: $stage"
    $beforeAudit=Get-AuditSnapshot
    $plan=@(Get-UninstallPlan $state $before $Mode)
    $stage='Stopping task and restoring managed policies'
    Write-Output "Stage: $stage"
    $changed=$true
    if ($null -ne $task) {$task.Enabled=$false; $task.Stop(0)}
    foreach ($p in $plan) {
        Set-RegistrySnapshot $p
        if (-not (Test-SnapshotEqual (Get-RegistrySnapshot $p.Name) $p)) {throw "Uninstall verification failed: $($p.Name)"}
    }
    $stage='Restoring registry audit permissions'
    Write-Output "Stage: $stage"
    Restore-ManagerAudit $root
    if ($null -ne $task) {$service.GetFolder('\').DeleteTask('ClaudePolicyManager-Enforce',0)}
    Write-ManagerLog $root "Uninstall succeeded; mode=$Mode; registry values changed=$($plan.Count)."
    # Task is unregistered before the lock is released and files are removed.
    $lock.Dispose(); $lock=$null
    $changed=$false
    $stage='Checking manager folder'
    Write-Output "Stage: $stage"
    $null=@(Get-SafeTree $root)
    $stage='Removing installed manager files'
    Write-Output "Stage: $stage"
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
    Write-Output "Claude policy manager removed ($Mode)."
    exit 0
} catch {
    $failureRecord=$_
    $failure=$failureRecord.Exception.Message
    Write-Output "UNINSTALL FAILED during stage: $stage"
    Write-Output ($failureRecord | Format-List * -Force | Out-String -Width 240)
    Write-Output ("Position: {0}" -f $failureRecord.InvocationInfo.PositionMessage)
    Write-Output ("Script stack: {0}" -f $failureRecord.ScriptStackTrace)
    if ($changed) {
        try {
            foreach ($p in $before) {Set-RegistrySnapshot $p}
            if ($null -ne $beforeAudit) {Set-AuditSnapshot $beforeAudit}
            if ($null -ne $beforeState) {Write-AtomicBytes (Join-Path $root 'State.json') $beforeState}
            if ($null -ne $definition) {
                [void]$service.GetFolder('\').RegisterTaskDefinition('ClaudePolicyManager-Enforce',$definition,22,'SYSTEM',$null,5,$sddl)
                (Get-ManagerTask $service).Enabled=$wasEnabled
            }
            Write-ManagerLog $root "Uninstall failed; enforcement restored: $failure"
        } catch {Write-Error "Uninstall rollback failed: $($_.Exception.Message)" -ErrorAction Continue}
    }
    Write-Error "Uninstall failed: $failure" -ErrorAction Continue
    exit 1
} finally {if ($null -ne $lock) {$lock.Dispose()}}
