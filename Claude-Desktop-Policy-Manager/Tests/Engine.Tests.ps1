#requires -Version 5.1
# Portable logic tests: no Windows registry, task, auditing, or ACL mutations.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $root 'Source/PolicyEngine.psm1') -Force -PassThru -DisableNameChecking
$script:Count=0
function Assert($Condition,[string]$Message) {
    if (-not $Condition) {throw "FAIL: $Message"}; $script:Count++; Write-Output "PASS: $Message"
}
function MustThrow([scriptblock]$Action,[string]$Message) {
    $thrown=$false;try {& $Action | Out-Null} catch {$thrown=$true};Assert $thrown $Message
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudePolicyTests-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
try {
    foreach ($file in Get-ChildItem $root -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1')}) {
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) "Parser: $($file.Name)"
    }
    $config1=Read-PolicyConfiguration (Join-Path $root 'Examples/Config-1-ChatOnly.json')
    $config2=Read-PolicyConfiguration (Join-Path $root 'Examples/Config-2-AllowCode.json')
    Assert ($config1.Desired.Count -eq 6) 'Config 1 contains six enforced policies'
    Assert ($config2.Desired.Count -eq 2) 'Config 2 contains two new instructions'
    MustThrow {Read-PolicyConfiguration (Join-Path $root 'Source/PolicyConfig.json')} 'Uncustomized shipping template is rejected'
    MustThrow {Read-PolicyConfiguration (Join-Path $root 'Examples/All-Settings.example.json')} 'Placeholder organization ID is rejected'
    foreach ($item in @(@($true,1),@($false,0),@(1,1),@(0,0))) {
        Assert ((Convert-PolicyValue isLocalDevMcpEnabled $item[0]).Value -eq $item[1]) "Boolean conversion $($item[0])"
    }
    foreach ($v in @('false','1',2,-1,1.5)) {MustThrow {Convert-PolicyValue disableAutoUpdates $v} "Reject invalid boolean: $v"}
    foreach ($v in @(1,72)) {Assert ((Convert-PolicyValue autoUpdaterEnforcementHours $v).Value -eq $v) "Accept hour boundary $v"}
    foreach ($v in @(0,73,'72',2.5)) {MustThrow {Convert-PolicyValue autoUpdaterEnforcementHours $v} "Reject invalid hours $v"}
    foreach ($v in @('low','medium','high','xhigh','max')) {Assert ((Convert-PolicyValue effortLevel $v).Value -ceq $v) "Effort value $v"}
    MustThrow {Convert-PolicyValue effortLevel 'High'} 'Effort is case sensitive'
    MustThrow {Convert-PolicyValue unknownKey 1} 'Arbitrary registry names are rejected'
    $id='11111111-1111-4111-8111-111111111111'
    Assert ((Convert-PolicyValue forceLoginOrgUUID $id).Value -eq $id) 'Single organization is a plain string'
    $org=Convert-PolicyValue forceLoginOrgUUID @($id)
    Assert ($org.Kind -eq 'String' -and $org.Value -eq ('["'+$id+'"]')) 'One-item organization array remains JSON REG_SZ'
    MustThrow {Convert-PolicyValue forceLoginOrgUUID @()} 'Empty organization list is rejected'
    $folders=Convert-PolicyValue allowedWorkspaceFolders @('C:\Approved','\\server\share\folder')
    Assert (($folders.Value | ConvertFrom-Json)[0] -eq 'C:\Approved') 'Folder JSON round-trips Windows backslashes'
    foreach ($v in @(@(),@('relative'),@('%USERPROFILE%\Documents'),@('C:\X\..\Y'))) {MustThrow {Convert-PolicyValue allowedWorkspaceFolders $v} 'Invalid folder input is rejected'}
    $full=Get-Content (Join-Path $root 'Examples/All-Settings.example.json') -Raw | ConvertFrom-Json
    $full.Policies.forceLoginOrgUUID=@($id)
    $full.Policies.coworkEDRIntegrationVendor='vendor-test'
    $fullPath=Join-Path $temp 'full.json';$full | ConvertTo-Json -Depth 10 | Set-Content $fullPath
    Assert ((Read-PolicyConfiguration $fullPath).Desired.Count -eq 12) 'All twelve settings validate and normalize together'
    $bad=Get-Content $fullPath -Raw | ConvertFrom-Json
    $bad.RemovePolicies=@('effortLevel');$bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $temp 'bad.json')
    MustThrow {Read-PolicyConfiguration (Join-Path $temp 'bad.json')} 'Set/remove overlap is rejected'
    $bad.Policies.effortLevel=$null;$bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $temp 'bad.json')
    $removal=Read-PolicyConfiguration (Join-Path $temp 'bad.json')
    Assert (-not @($removal.Desired | Where-Object Name -eq 'effortLevel')[0].Present) 'Explicit removal creates an absent-value instruction'
    $bad.RemovePolicies=@('effortLevel','effortLevel');$bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $temp 'bad.json')
    MustThrow {Read-PolicyConfiguration (Join-Path $temp 'bad.json')} 'Duplicate removal is rejected'
    $merged=@(Get-MergedPolicySet $config1.Desired $config2.Desired)
    Assert ($merged.Count -eq 7) 'Config switch retains omitted protections'
    Assert (@($merged | Where-Object Name -eq isClaudeCodeForDesktopEnabled)[0].Value -eq 1) 'Config 2 replaces the selected Config 1 value'
    Assert (@($merged | Where-Object Name -eq isLocalDevMcpEnabled)[0].Value -eq 0) 'Config 2 preserves Config 1 MCP restriction'
    $ordered=@(Get-MergedPolicySet $merged @([pscustomobject]@{Name='effortLevel';Present=$false;Kind=$null;Value=$null}))
    Assert ($ordered[-1].Name -eq 'effortLevel' -and -not $ordered[-1].Present) 'Explicit removal runs after present-value writes'
    $query=[xml](Get-RegistryEventQuery)
    Assert ($query.QueryList.Query.Select.InnerText -match '4657' -and $query.QueryList.Query.Select.InnerText -match '4663') 'Registry event query includes value and object-access events'
    Assert ($query.QueryList.Query.Select.InnerText.Contains('\REGISTRY\MACHINE\SOFTWARE\Policies\Claude')) 'Event filter is limited to the Claude key'
    # Replace only OS side-effect functions with in-memory fixtures, then exercise the real enforcement/state logic.
    & $module {
        $script:FakeRegistry=@{}; $script:Writes=0; $script:FailOnName=$null
        function script:Get-RegistrySnapshot([string]$Name) {
            if ($script:FakeRegistry.ContainsKey($Name)) {return $script:FakeRegistry[$Name]}
            [pscustomobject]@{Name=$Name;Present=$false;Kind=$null;Value=$null}
        }
        function script:Set-RegistrySnapshot($Snapshot) {
            if ($Snapshot.Name -eq $script:FailOnName) {throw 'Injected registry failure'}
            $script:FakeRegistry[$Snapshot.Name]=$Snapshot;$script:Writes++
        }
        function script:Write-PrivateJson([string]$Path,$Object) {
            [IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Object -Depth 20))
        }
        function script:Write-ManagerLog([string]$Root,[string]$Message) {}
    }
    [IO.File]::WriteAllText((Join-Path $temp 'State.json'),' {"SchemaVersion":1,"Original":[],"LastDesired":[]} ')
    $changes=Invoke-PolicyEnforcement $temp $config1
    Assert ($changes -eq 6) 'First enforcement creates missing values'
    Assert ((Invoke-PolicyEnforcement $temp $config1) -eq 0) 'Second enforcement is idempotent'
    & $module {$script:FakeRegistry['isLocalDevMcpEnabled']=[pscustomobject]@{Name='isLocalDevMcpEnabled';Present=$true;Kind='String';Value='0'}}
    Assert ((Invoke-PolicyEnforcement $temp $config1) -eq 1) 'Wrong registry type is repaired even when displayed value matches'
    & $module {$script:FakeRegistry.Remove('secureVmFeaturesEnabled')}
    Assert ((Invoke-PolicyEnforcement $temp $config1) -eq 1) 'Deleted registry value is recreated'
    Assert ((Invoke-PolicyEnforcement $temp $config2) -eq 2) 'Config update applies changed and new values only'
    $state=Read-ManagerState $temp
    Assert ($state.LastDesired.Count -eq 7 -and $state.Original.Count -eq 7) 'Update retains original backups and full active policy set'
    & $module {$script:FakeRegistry.Remove('isLocalDevMcpEnabled')}
    Assert ((Invoke-PolicyEnforcement $temp $config2) -eq 1) 'Config 2 still repairs an inherited Config 1 restriction'
    $current=@(& $module {param($s) $s.LastDesired | ForEach-Object {Get-RegistrySnapshot $_.Name}} $state)
    $plan=@(Get-UninstallPlan $state $current 'RestoreOriginal')
    Assert ($plan.Count -eq 7 -and @($plan | Where-Object Present).Count -eq 0) 'Uninstall restores originally absent values to absent'
    $current[0]=[pscustomobject]@{Name=$current[0].Name;Present=$true;Kind='String';Value='external-change'}
    Assert (@(Get-UninstallPlan $state $current 'RemoveManaged').Count -eq 6) 'Uninstall preserves values changed by another owner'
    Assert (@(Get-UninstallPlan $state $current 'KeepPolicies').Count -eq 0) 'KeepPolicies mode does not modify registry values'
    $removeConfig=[pscustomobject]@{ConfigurationId='Remove-Test';Desired=@([pscustomobject]@{Name='effortLevel';Present=$false;Kind=$null;Value=$null})}
    Assert ((Invoke-PolicyEnforcement $temp $removeConfig) -eq 1) 'RemovePolicies deletes a managed value'
    & $module {$script:FakeRegistry['effortLevel']=[pscustomobject]@{Name='effortLevel';Present=$true;Kind='String';Value='low'}}
    Assert ((Invoke-PolicyEnforcement $temp $removeConfig) -eq 1) 'Deleted-policy enforcement removes recreated values'
    & $module {$script:FailOnName='autoUpdaterEnforcementHours'}
    $failing=[pscustomobject]@{ConfigurationId='Failure-Test';Desired=@((Convert-PolicyValue autoUpdaterEnforcementHours 24))}
    MustThrow {Invoke-PolicyEnforcement $temp $failing} 'Registry write failures do not report success'
    Assert (@((Read-ManagerState $temp).Original | Where-Object Name -eq autoUpdaterEnforcementHours).Count -eq 1) 'Backup is persisted before a failing registry write'
    Write-Output "SUCCESS: $script:Count checks. Windows integration tests remain required."
} finally {
    Remove-Module $module -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
