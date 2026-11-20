#requires -Version 5.1
# Optional native Windows test. Run in native Windows PowerShell as SYSTEM.
# Only a unique temporary ProgramData directory is modified; no live manager,
# Claude policies, scheduled tasks, or audit settings are changed.
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Source/PolicyEngine.psm1') -Force -DisableNameChecking
Assert-Administrator
$area=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) ('ClaudePolicyManager-AclPilot-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $area 'Manager';$lock=$null
try {
 New-PrivateDirectory $area
 Initialize-PrivateRoot $root
 $lock=Enter-ManagerLock $root
 Repair-PrivateTree $root
 Write-PrivateJson (Join-Path $root 'State.json') ([ordered]@{SchemaVersion=1;Original=@();LastDesired=@()})
 $lock.Dispose();$lock=$null;Set-PrivatePermissions (Join-Path $root 'Operation.lock')
 $state=Join-Path $root 'State.json';$hash=Get-FileDigest $state
 foreach ($path in @($root,$state)) {
  $acl=Get-Acl -LiteralPath $path
  $sid=New-Object Security.Principal.SecurityIdentifier('S-1-12-1-111-222-333-444')
  $inherit=[Security.AccessControl.InheritanceFlags]::None
  if ($path -eq $root) {$inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit}
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
  $acl.AddAccessRule($rule);Set-Acl -LiteralPath $path -AclObject $acl
 }
 Initialize-PrivateRoot $root
 $lock=Enter-ManagerLock $root;Repair-PrivateTree $root
 Assert-PrivatePermissions $root;Assert-PrivatePermissions $state
 if ((Get-FileDigest $state) -cne $hash) {throw 'State file changed during ACL repair'}
 $lock.Dispose();$lock=$null;Set-PrivatePermissions (Join-Path $root 'Operation.lock')
 $acl=Get-Acl -LiteralPath $state;$acl.SetAccessRuleProtection($false,$true);Set-Acl -LiteralPath $state -AclObject $acl
 Initialize-PrivateRoot $root;$lock=Enter-ManagerLock $root;Repair-PrivateTree $root
 Assert-PrivatePermissions $root;Assert-PrivatePermissions $state
 if ((Get-FileDigest $state) -cne $hash) {throw 'State file changed during inheritance repair'}
 Write-Output 'PASS: Native extra-SID root/file ACL repair, inheritance repair, and state-byte preservation.'
} finally {
 if ($null -ne $lock) {$lock.Dispose()}
 if (Test-Path -LiteralPath $area) {Remove-Item -LiteralPath $area -Recurse -Force -ErrorAction Stop}
}
