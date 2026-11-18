#requires -Version 5.1
# Runs the actual installer/uninstaller against a disposable filesystem and simulated
# Windows services. It NEVER touches the real registry, task scheduler, ACLs, or auditing.
$ErrorActionPreference='Stop'
$bundle=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeTransaction-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $temp)
$script:Count=0
function Assert($ok,$text) {if (-not $ok) {throw "FAIL: $text"};$script:Count++;Write-Output "PASS: $text"}
$mocks=@'
function Get-ManagerRoot {Join-Path $env:CPM_TEST_AREA 'Installed'}
function Assert-Administrator {}
function Set-PrivatePermissions([string]$Path,[switch]$Directory) {}
function Assert-PrivatePermissions([string]$Path) {}
function Initialize-PrivateRoot([string]$Root) {if (-not (Test-Path $Root)) {[void](New-Item -ItemType Directory $Root)}}
function Get-AuditSnapshot {return $null}
function Set-AuditSnapshot($Snapshot) {}
function Ensure-RegistryAuditing([string]$Root,$Config,[switch]$Install) {}
function Restore-ManagerAudit([string]$Root) {}
function Read-FakeRegistry {
 $p=Join-Path $env:CPM_TEST_AREA 'registry.json'
 if (Test-Path $p) {Get-Content $p -Raw | ConvertFrom-Json}
}
function Get-RegistrySnapshot([string]$Name) {
 $p=@(Read-FakeRegistry | Where-Object Name -eq $Name)
 if ($p.Count) {return $p[0]}
 [pscustomobject]@{Name=$Name;Present=$false;Kind=$null;Value=$null}
}
function Set-RegistrySnapshot($Snapshot) {
 $all=@(Read-FakeRegistry | Where-Object Name -ne $Snapshot.Name)+@($Snapshot)
 [IO.File]::WriteAllText((Join-Path $env:CPM_TEST_AREA 'registry.json'),(ConvertTo-Json -InputObject $all -Depth 10))
}
function New-FakeTask($Definition,[bool]$Enabled=$true) {
 $t=[pscustomobject]@{Definition=$Definition;Enabled=$Enabled}
 $t | Add-Member ScriptMethod GetSecurityDescriptor {param($flags) 'O:SYG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)'}
 $t | Add-Member ScriptMethod Stop {param($flags)}
 return $t
}
function Save-FakeTask($Task) {
 [IO.File]::WriteAllText((Join-Path $env:CPM_TEST_AREA 'task.json'),($Task | ConvertTo-Json -Depth 10))
}
function Get-ManagerTask($Service) {
 $p=Join-Path $env:CPM_TEST_AREA 'task.json'
 if (-not (Test-Path $p)) {return $null}
 $o=Get-Content $p -Raw | ConvertFrom-Json
 New-FakeTask $o.Definition $o.Enabled
}
function Connect-TaskService {
 $folder=New-Object psobject
 $folder | Add-Member ScriptMethod DeleteTask {param($n,$f) Remove-Item (Join-Path $env:CPM_TEST_AREA 'task.json') -Force -ErrorAction SilentlyContinue}
 $folder | Add-Member ScriptMethod RegisterTaskDefinition {
  param($name,$definition,$flags,$user,$password,$logon,$sddl)
  $t=New-FakeTask $definition;Save-FakeTask $t;return $t
 }
 $service=[pscustomobject]@{Folder=$folder}
 $service | Add-Member ScriptMethod GetFolder {param($p) $this.Folder}
 return $service
}
function Register-ManagerTask($Service,[string]$Root,$Config) {
 $d=[pscustomobject]@{RegistrationInfo=[pscustomobject]@{Description="ClaudePolicyManager managed task; $($Config.ConfigurationId)"}}
 Save-FakeTask (New-FakeTask $d)
}
function Assert-InstallationHealthy([string]$Root) {
 $null=Read-PackageManifest $Root
 if ($env:CPM_TEST_FAIL_HEALTH -eq '1') {throw 'Injected post-registration verification failure'}
 $c=Read-PolicyConfiguration (Join-Path $Root 'PolicyConfig.json')
 $s=Read-ManagerState $Root
 foreach ($d in @(Get-MergedPolicySet $s.LastDesired $c.Desired)) {
  if (-not (Test-SnapshotEqual (Get-RegistrySnapshot $d.Name) $d)) {throw 'Simulated registry does not match'}
 }
}
Export-ModuleMember -Function *
'@
function Build-FakePackage([string]$Name,[string]$Example) {
 $dest=Join-Path $temp $Name
 [void](New-Item -ItemType Directory $dest)
 Copy-Item (Join-Path $bundle 'Source/*') $dest
 $module=Join-Path $dest 'PolicyEngine.psm1'
 [IO.File]::AppendAllText($module,[Environment]::NewLine+$mocks)
 Copy-Item (Join-Path $bundle "Examples/$Example") (Join-Path $dest 'PolicyConfig.json') -Force
 $config=Get-Content (Join-Path $dest 'PolicyConfig.json') -Raw | ConvertFrom-Json
 $files=[ordered]@{}
 foreach ($n in @('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1')) {$files[$n]=(Get-FileHash (Join-Path $dest $n)).Hash.ToLowerInvariant()}
 $manifest=[ordered]@{SchemaVersion=1;PackageVersion='1.0.1';ConfigurationId=$config.ConfigurationId;Files=$files}
 $manifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dest 'PackageManifest.json')
 return $dest
}
function ActiveRegistry {
 $path=Join-Path $temp 'registry.json'
 $active=@(Get-Content $path -Raw | ConvertFrom-Json | Where-Object Present | Sort-Object Name)
 ConvertTo-Json -InputObject $active -Depth 10 -Compress
}
try {
 $exe=Join-Path $PSHOME 'pwsh';if (-not (Test-Path $exe)) {$exe=Join-Path $PSHOME 'powershell.exe'}
 $env:CPM_TEST_AREA=$temp
 $a=Build-FakePackage 'A' 'Config-1-ChatOnly.json'
 $b=Build-FakePackage 'B' 'Config-2-AllowCode.json'
 $installed=Join-Path $temp 'Installed'
 & $exe -NoProfile -File (Join-Path $a 'Install-PolicyManager.ps1') | Out-Null
 Assert ($LASTEXITCODE -eq 0) 'Initial install transaction succeeds'
 $originalManifest=(Get-FileHash (Join-Path $installed 'PackageManifest.json')).Hash
 $originalState=(Get-FileHash (Join-Path $installed 'State.json')).Hash
 $originalRegistry=ActiveRegistry
 $originalTask=Get-Content (Join-Path $temp 'task.json') -Raw
 $env:CPM_TEST_FAIL_HEALTH='1'
 $failureOutput=& $exe -NoProfile -File (Join-Path $b 'Install-PolicyManager.ps1') 2>&1
 Assert ($LASTEXITCODE -eq 1) 'Post-update verification failure reports failure'
 Assert ((Get-FileHash (Join-Path $installed 'PackageManifest.json')).Hash -eq $originalManifest) 'Failed update restores original package files'
 Assert ((Get-FileHash (Join-Path $installed 'State.json')).Hash -eq $originalState) 'Failed update restores original enforcement/backup state'
 Assert ((ActiveRegistry) -ceq $originalRegistry) 'Failed update rolls back all changed registry values'
 Assert ((Get-Content (Join-Path $temp 'task.json') -Raw) -ceq $originalTask) 'Failed update restores previous scheduled-task definition'
 $env:CPM_TEST_FAIL_HEALTH='0'
 & $exe -NoProfile -File (Join-Path $b 'Install-PolicyManager.ps1') | Out-Null
 Assert ($LASTEXITCODE -eq 0) 'Subsequent update succeeds without an uninstall'
 $state=Get-Content (Join-Path $installed 'State.json') -Raw | ConvertFrom-Json
 Assert ($state.LastDesired.Count -eq 7) 'Successful switch retains protections and adds the new policy'
 $registryB=ActiveRegistry
 & $exe -NoProfile -File (Join-Path $a 'Uninstall-PolicyManager.ps1') | Out-Null
 Assert ($LASTEXITCODE -eq 0 -and (Test-Path $installed)) 'Delayed uninstall from old package skips the newer manager'
 Assert ((ActiveRegistry) -ceq $registryB) 'Old uninstall leaves newer registry policy unchanged'
 & $exe -NoProfile -File (Join-Path $b 'Uninstall-PolicyManager.ps1') | Out-Null
 Assert ($LASTEXITCODE -eq 0 -and -not (Test-Path $installed)) 'Matching uninstall removes the installed manager'
 Assert (-not (Test-Path (Join-Path $temp 'task.json'))) 'Matching uninstall removes the scheduled task'
 Assert ((ActiveRegistry) -eq '[]') 'Matching uninstall restores the original registry state'
 Write-Output "SUCCESS: $script:Count transaction checks with simulated Windows services."
} finally {
 Remove-Item Env:CPM_TEST_AREA -ErrorAction SilentlyContinue
 Remove-Item Env:CPM_TEST_FAIL_HEALTH -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
