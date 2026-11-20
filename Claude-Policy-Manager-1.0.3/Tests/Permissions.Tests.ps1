#requires -Version 5.1
# Production repair/identity/order logic against real temporary files and mocked
# ACL reads/writes. Native NTFS integration is covered by Windows-ACL.Tests.ps1.
$ErrorActionPreference='Stop'
$bundle=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $bundle 'Source/PolicyEngine.psm1') -Force -PassThru -DisableNameChecking
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeAcl-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $temp)
$script:Count=0
function Assert($ok,$text) {if (-not $ok) {throw "FAIL: $text"};$script:Count++;Write-Output "PASS: $text"}
function MustThrow([scriptblock]$Action,[string]$pattern,[string]$message) {
 $failure=$null;try {& $Action | Out-Null} catch {$failure=$_}
 Assert ($null -ne $failure -and $failure.Exception.Message -match $pattern) $message
}
& $module {
 $script:AclMap=@{};$script:AclWrites=0;$script:FailAclPath='';$script:IgnoreAclPath=''
 function script:New-TestAcl([bool]$Directory) {
  $inheritance=0;if ($Directory) {$inheritance=3}
  [pscustomobject]@{Owner='S-1-5-18';Protected=$true;Sddl='canonical';Rules=@(
   [pscustomobject]@{Sid='S-1-5-18';Rights=0x1f01ff;Type='Allow';Inherited=$false;Inheritance=$inheritance;Propagation=0},
   [pscustomobject]@{Sid='S-1-5-32-544';Rights=0x1f01ff;Type='Allow';Inherited=$false;Inheritance=$inheritance;Propagation=0}
  )}
 }
 function script:Get-PrivateAclInfo([string]$Path) {
  if (-not $script:AclMap.ContainsKey($Path)) {$script:AclMap[$Path]=New-TestAcl (Get-Item -LiteralPath $Path).PSIsContainer}
  $script:AclMap[$Path]
 }
 function script:Set-PrivatePermissions([string]$Path,[switch]$Directory) {
  if ($Path -eq $script:FailAclPath) {throw 'Injected Set-Acl failure'}
  if ($Path -eq $script:IgnoreAclPath) {return}
  $script:AclMap[$Path]=New-TestAcl $Directory.IsPresent;$script:AclWrites++
 }
 function script:New-PrivateDirectory([string]$Root) {[void](New-Item -ItemType Directory $Root);$script:AclMap[$Root]=New-TestAcl $true}
 Export-ModuleMember -Function *
}
function Read-TestAcl([string]$Path) { & $module {param($p) Get-PrivateAclInfo $p} $Path }
function Make-OwnedFolder([string]$Name) {
 $p=Join-Path $temp $Name;[void](New-Item -ItemType Directory $p)
 [IO.File]::WriteAllText((Join-Path $p 'Owner.json'),'{"Product":"ClaudePolicyManager","SchemaVersion":1}')
 return $p
}
function Add-ExtraRule([string]$Path,[string]$Sid='S-1-12-1-111-222-333-444') {
 & $module {param($p,$sid)
  $a=Get-PrivateAclInfo $p
  $a.Rules+= [pscustomobject]@{Sid=$sid;Rights=0x1f01ff;Type='Allow';Inherited=$false;Inheritance=3;Propagation=0}
  $a.Sddl='extra-full-control-'+$sid
 } $Path $Sid
}
try {
 $fresh=Join-Path $temp 'Fresh'
 Initialize-PrivateRoot $fresh | Out-Null
 [IO.File]::WriteAllText((Join-Path $fresh 'Operation.lock'),'')
 Repair-PrivateTree $fresh | Out-Null
 Assert (Test-Path (Join-Path $fresh 'Owner.json')) 'Fresh lock-only folder is adopted and receives ownership marker'
 $root=Make-OwnedFolder 'ReportedCase'
 $state=Join-Path $root 'State.json';[IO.File]::WriteAllText($state,'{"Original":[],"LastDesired":[]}')
 $beforeHash=(Get-FileHash $state).Hash
 Add-ExtraRule $root;Add-ExtraRule $state
 $out=@(Initialize-PrivateRoot $root;Repair-PrivateTree $root) | Out-String
 Assert (Test-PrivateAclInfo (Read-TestAcl $root) $true) 'Reported third Entra SID rule is removed automatically'
 Assert (Test-PrivateAclInfo (Read-TestAcl $state) $false) 'Child-file ACL drift is repaired automatically'
 Assert ((Get-FileHash $state).Hash -eq $beforeHash) 'Repair preserves existing state-file bytes'
 Assert ($out -match 'ACL repair:' -and $out -match 'before=extra-full-control' -and $out -match 'after=canonical') 'Repair logs before and after permissions'
 $out=@(Initialize-PrivateRoot $root;Repair-PrivateTree $root) | Out-String
 Assert ($out -notmatch 'ACL repair:') 'Canonical permissions do not trigger repeat repairs'
 & $module {param($p) $a=Get-PrivateAclInfo $p;$a.Protected=$false;$a.Rules[0].Inherited=$true;$a.Sddl='inherited'} $state
 Repair-PrivateTree $root | Out-Null
 Assert (Test-PrivateAclInfo (Read-TestAcl $state) $false) 'Inheritance drift is repaired'
 & $module {param($p) $a=Get-PrivateAclInfo $p;$a.Rules[1].Rights=131209;$a.Sddl='admin-read-only'} $state
 Repair-PrivateTree $root | Out-Null
 Assert (Test-PrivateAclInfo (Read-TestAcl $state) $false) 'Missing administrator full-control rights are restored'
 $bad=Make-OwnedFolder 'ForeignContent';Add-ExtraRule $bad
 [IO.File]::WriteAllText((Join-Path $bad 'unrelated.txt'),'leave this alone')
 MustThrow {Initialize-PrivateRoot $bad} 'Unrecognized' 'Unknown files prevent automatic folder adoption'
 Assert (@((Read-TestAcl $bad).Rules).Count -eq 3) 'Unknown-content refusal occurs before changing root ACL'
 $bad=Make-OwnedFolder 'UnexpectedOwner';Add-ExtraRule $bad
 $file=Join-Path $bad 'State.json';[IO.File]::WriteAllText($file,'{}')
 & $module {param($p) (Get-PrivateAclInfo $p).Owner='S-1-5-21-1-2-3-1001'} $file
 MustThrow {Initialize-PrivateRoot $bad} 'Unexpected owner' 'Unexpected child owner stops repair'
 Assert (@((Read-TestAcl $bad).Rules).Count -eq 3) 'Complete owner preflight happens before root mutation'
 $bad=Make-OwnedFolder 'InvalidMarker';Add-ExtraRule $bad
 [IO.File]::WriteAllText((Join-Path $bad 'Owner.json'),'{"Product":"DifferentProduct","SchemaVersion":1}')
 MustThrow {Initialize-PrivateRoot $bad} 'Invalid manager ownership' 'A foreign product marker is rejected'
 $bad=Join-Path $temp 'NoMarker';[void](New-Item -ItemType Directory $bad)
 [IO.File]::WriteAllText((Join-Path $bad 'State.json'),'{}')
 MustThrow {Initialize-PrivateRoot $bad} 'no valid manager' 'Unmarked nonempty folder is rejected'
 $fallback=Make-OwnedFolder 'ManifestFallback';Remove-Item (Join-Path $fallback 'Owner.json')
 $hash='a'*64
 @{SchemaVersion=1;PackageVersion='1.0.2';ConfigurationId='previous';Files=@{'PolicyEngine.psm1'=$hash;'PolicyConfig.json'=$hash;'Enforce-Policies.ps1'=$hash}} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fallback 'PackageManifest.json')
 Add-ExtraRule $fallback;Initialize-PrivateRoot $fallback | Out-Null;Repair-PrivateTree $fallback | Out-Null
 Assert (Test-Path (Join-Path $fallback 'Owner.json')) 'Previous-version manifest allows repair and marker recovery'
 $bad=Make-OwnedFolder 'SetAclFailure';Add-ExtraRule $bad
 & $module {param($p) $script:FailAclPath=$p} $bad
 MustThrow {Initialize-PrivateRoot $bad} 'Injected Set-Acl failure' 'A failed ACL write does not report successful repair'
 & $module {$script:FailAclPath=''}
 $bad=Make-OwnedFolder 'VerificationFailure';Add-ExtraRule $bad
 & $module {param($p) $script:IgnoreAclPath=$p} $bad
 MustThrow {Initialize-PrivateRoot $bad} 'Unexpected ACL' 'Post-repair verification detects an ineffective ACL write'
 & $module {$script:IgnoreAclPath=''}
 $bad=Make-OwnedFolder 'Redirected';Add-ExtraRule $bad
 $outside=Join-Path $temp 'Outside';[void](New-Item -ItemType Directory $outside)
 $link=Join-Path $bad 'State.json'
 try {$null=New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop} catch {Write-Output 'SKIP: host cannot create symlinks for reparse test.'}
 if (Test-Path -LiteralPath $link) {
  MustThrow {Initialize-PrivateRoot $bad} 'reparse point' 'Reparse points are refused before ACL repair'
  Assert (@((Read-TestAcl $bad).Rules).Count -eq 3) 'Reparse refusal leaves root permissions untouched'
  Remove-Item -LiteralPath $link -Force
 }
 Write-Output "SUCCESS: $script:Count permission-repair checks using simulated ACLs."
} finally {Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
