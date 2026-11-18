#requires -Version 5.1
Set-StrictMode -Version 2.0
$script:Version = '1.0.1'
$script:RegistryPath = 'SOFTWARE\Policies\Claude'
$script:TaskName = 'ClaudePolicyManager-Enforce'
$script:TaskMarker = 'ClaudePolicyManager managed task'
$script:PayloadNames = @('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1')
$script:PolicyTypes = [ordered]@{
    disableAutoUpdates='Boolean'; autoUpdaterEnforcementHours='Hours'
    isDesktopExtensionEnabled='Boolean'; isDesktopExtensionDirectoryEnabled='Boolean'
    isLocalDevMcpEnabled='Boolean'; isClaudeCodeForDesktopEnabled='Boolean'
    secureVmFeaturesEnabled='Boolean'; forceLoginOrgUUID='Organizations'
    allowedWorkspaceFolders='Folders'; effortLevel='Effort'
    coworkEDRIntegration='Path'; coworkEDRIntegrationVendor='Vendor'
}

function Get-ManagerRoot { Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ClaudePolicyManager' }
function Get-ManagerVersion { $script:Version }
function Assert-Administrator {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows is required.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Run using native 64-bit Windows PowerShell. Use Install.cmd or Uninstall.cmd.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { throw 'Run as SYSTEM (Intune install behavior: System). Local testing also requires a SYSTEM console.' }
}
function Assert-Properties($Object, [string[]]$Allowed, [string]$Label) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw "$Label must be a JSON object." }
    foreach ($p in $Object.PSObject.Properties) {
        if ($Allowed -cnotcontains $p.Name) { throw "Unknown or incorrectly cased property $Label.$($p.Name)." }
    }
}
function Get-Property($Object, [string]$Name, $Default=$null) {
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return ,$Default }
    return ,$p.Value
}
function Test-Integer($Value) { ($Value -is [int] -or $Value -is [long]) }
function Assert-AbsoluteWindowsPath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '[\x00-\x1f"<>|?*%]') { throw 'Use a concrete absolute Windows path, without quotes, wildcards, or environment variables.' }
    if ($Value -match '^[A-Za-z]:\\') { $tail=$Value.Substring(2) }
    elseif ($Value -match '^\\\\[^\\]+\\[^\\]+') { $tail=$Value }
    else { throw "Not an absolute Windows path: $Value" }
    if ($tail.Contains(':') -or $Value -match '(^|\\)\.\.(\\|$)') { throw "Invalid path: $Value" }
}
function Convert-PolicyValue([string]$Name, $Value) {
    if (@($script:PolicyTypes.Keys) -cnotcontains $Name) { throw "Unsupported policy: $Name" }
    $kind='String'; $data=$null
    switch ($script:PolicyTypes[$Name]) {
        Boolean {
            $kind='DWord'
            if ($Value -is [bool]) { $data=[int]$Value }
            elseif ((Test-Integer $Value) -and $Value -in @(0,1)) { $data=[int]$Value }
            else { throw "$Name requires a JSON boolean or integer 0/1." }
        }
        Hours {
            $kind='DWord'
            if (-not (Test-Integer $Value) -or $Value -lt 1 -or $Value -gt 72) { throw "$Name requires an integer from 1 to 72." }
            $data=[int]$Value
        }
        Organizations {
            $isArray=$Value -is [array]
            if (-not $isArray -and $Value -isnot [string]) { throw "$Name requires a UUID string or an array of UUID strings." }
            $ids=@($Value)
            if ($ids.Count -eq 0) { throw "$Name cannot be an empty array." }
            foreach ($id in $ids) {
                $guid=[guid]::Empty
                if ($id -isnot [string] -or -not [guid]::TryParseExact($id,'D',[ref]$guid) -or $guid -eq [guid]::Empty) { throw "$Name contains an invalid UUID; replace any placeholder." }
            }
            if ($isArray) { $data=ConvertTo-Json -InputObject ([object[]]$ids) -Compress } else { $data=$ids[0] }
        }
        Folders {
            if ($Value -isnot [array] -or $Value.Count -eq 0) { throw "$Name requires a nonempty JSON array of absolute folder paths." }
            foreach ($folder in $Value) {
                if ($folder -isnot [string]) { throw "$Name entries must be strings." }
                Assert-AbsoluteWindowsPath $folder
            }
            $data=ConvertTo-Json -InputObject ([object[]]$Value) -Compress
        }
        Effort {
            if ($Value -isnot [string] -or @('low','medium','high','xhigh','max') -cnotcontains $Value) { throw 'effortLevel must be low, medium, high, xhigh, or max.' }
            $data=$Value
        }
        Path {
            if ($Value -isnot [string]) { throw "$Name must be a string." }
            Assert-AbsoluteWindowsPath $Value; $data=$Value
        }
        Vendor {
            if ($Value -isnot [string] -or $Value -cnotmatch '^[a-z][a-z0-9_-]{0,127}$') { throw "$Name requires a lowercase vendor identifier." }
            $data=$Value
        }
    }
    [pscustomobject]@{ Name=$Name; Present=$true; Kind=$kind; Value=$data }
}
function Read-PolicyConfiguration([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Configuration missing: $Path" }
    if ((Get-Item -LiteralPath $Path).Length -gt 262144) { throw 'Configuration exceeds 256 KiB.' }
    $config=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-Properties $config @('SchemaVersion','ConfigurationId','Enforcement','Policies','RemovePolicies') 'Config'
    if ((Get-Property $config 'SchemaVersion') -ne 1) { throw 'SchemaVersion must be 1.' }
    $id=Get-Property $config 'ConfigurationId'
    if ($id -isnot [string] -or $id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$' -or $id -eq 'CHANGE-ME') { throw 'Set ConfigurationId to a meaningful name, using letters, digits, dots, underscores, or hyphens.' }
    $enforcement=Get-Property $config 'Enforcement'
    Assert-Properties $enforcement @('IntervalMinutes','RunAtStartup','RunAtLogon','RunOnRegistryChange','ConfigureAuditPolicy') 'Enforcement'
    $minutes=Get-Property $enforcement 'IntervalMinutes' 15
    if (-not (Test-Integer $minutes) -or $minutes -lt 1 -or $minutes -gt 1440) { throw 'IntervalMinutes must be an integer from 1 to 1440.' }
    $startup=Get-Property $enforcement 'RunAtStartup' $true
    $logon=Get-Property $enforcement 'RunAtLogon' $true
    if ($startup -isnot [bool] -or $logon -isnot [bool]) { throw 'RunAtStartup and RunAtLogon must be JSON booleans.' }
    $events=Get-Property $enforcement 'RunOnRegistryChange' $false
    $audit=Get-Property $enforcement 'ConfigureAuditPolicy' $false
    if ($events -isnot [bool] -or $audit -isnot [bool]) { throw 'RunOnRegistryChange and ConfigureAuditPolicy must be booleans.' }
    if ($audit -and -not $events) { throw 'ConfigureAuditPolicy requires RunOnRegistryChange.' }
    $policies=Get-Property $config 'Policies'
    Assert-Properties $policies @($script:PolicyTypes.Keys) 'Policies'
    $desired=New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $policies.PSObject.Properties) {
        if ($null -ne $p.Value) { $desired.Add((Convert-PolicyValue $p.Name $p.Value)) }
    }
    $remove=Get-Property $config 'RemovePolicies' @()
    if ($remove -isnot [array]) { throw 'RemovePolicies must be an array.' }
    $seen=@{}
    foreach ($name in $remove) {
        if ($name -isnot [string] -or @($script:PolicyTypes.Keys) -cnotcontains $name) { throw "Unsupported RemovePolicies entry: $name" }
        if ($seen.ContainsKey($name) -or @($desired | ForEach-Object {$_.Name}) -contains $name) { throw "Duplicate/conflicting managed policy: $name" }
        $seen[$name]=$true
        $desired.Add([pscustomobject]@{Name=$name;Present=$false;Kind=$null;Value=$null})
    }
    if ($desired.Count -eq 0) { throw 'Configure at least one non-null policy or RemovePolicies entry before deployment.' }
    [pscustomobject]@{ ConfigurationId=$id; IntervalMinutes=[int]$minutes; RunAtStartup=$startup; RunAtLogon=$logon; RunOnRegistryChange=$events; ConfigureAuditPolicy=$audit; Desired=@($desired.ToArray()) }
}
function Get-FileDigest([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
function Assert-NoReparse([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing reparse point: $Path" }
}
function Get-SafeTree([string]$Root) {
    Assert-NoReparse $Root
    Get-Item -LiteralPath $Root -Force
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($Root)) {
        Assert-NoReparse $path
        if ([IO.Directory]::Exists($path)) { Get-SafeTree $path } else { Get-Item -LiteralPath $path -Force }
    }
}
function Set-PrivatePermissions([string]$Path, [switch]$Directory) {
    if ($Directory) {
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $sddl='O:SYG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    } else {
        $acl=New-Object Security.AccessControl.FileSecurity
        $sddl='O:SYG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)'
    }
    $acl.SetSecurityDescriptorSddlForm($sddl)
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Assert-PrivatePermissions([string]$Path) {
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $acl.AreAccessRulesProtected) { throw "Permissions inherit at $Path" }
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-18') { throw "Unexpected owner at $Path" }
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne 2) { throw "Unexpected ACL at $Path" }
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $r=@($rules | Where-Object { $_.IdentityReference.Value -eq $sid })
        if ($r.Count -ne 1 -or $r[0].AccessControlType -ne 'Allow' -or $r[0].FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl) { throw "Unexpected permissions at $Path" }
    }
}
function Initialize-PrivateRoot([string]$Root) {
    # ProgramData is the OS-provided parent; do not accept a substituted parent junction.
    Assert-NoReparse (Split-Path $Root -Parent)
    if (-not (Test-Path -LiteralPath $Root)) {
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $acl.SetSecurityDescriptorSddlForm('O:SYG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
        [void][IO.Directory]::CreateDirectory($Root,$acl)
    }
    $items=@(Get-SafeTree $Root)
    if ($items.Count -gt 1) {
        Assert-PrivatePermissions $Root
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'Owner.json')) -and -not (Test-Path -LiteralPath (Join-Path $Root 'PackageManifest.json'))) { throw 'Destination contains unrelated files. Inspect the directory before installing.' }
    }
    foreach ($item in $items) { Set-PrivatePermissions $item.FullName -Directory:$item.PSIsContainer }
    Write-PrivateJson (Join-Path $Root 'Owner.json') ([ordered]@{Product='ClaudePolicyManager';SchemaVersion=1})
}
function Write-AtomicBytes([string]$Path, [byte[]]$Bytes) {
    $temp=Join-Path (Split-Path $Path -Parent) ('.new-'+[guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        Set-PrivatePermissions $temp
        if ([IO.File]::Exists($Path)) { Assert-NoReparse $Path; [IO.File]::Replace($temp,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
        Set-PrivatePermissions $Path
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Write-PrivateJson([string]$Path, $Object) {
    $text=ConvertTo-Json -InputObject $Object -Depth 20
    Write-AtomicBytes $Path ([Text.Encoding]::UTF8.GetBytes($text))
}
function Enter-ManagerLock([string]$Root) {
    $path=Join-Path $Root 'Operation.lock'
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do {
        try { $handle=[IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); return $handle }
        catch [IO.IOException] { Start-Sleep -Milliseconds 500 }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Another manager operation holds the lock. Retry later.'
}
function Write-ManagerLog([string]$Root, [string]$Message) {
    $path=Join-Path $Root 'PolicyManager.log'
    if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 2097152) {
        for ($i=2;$i -ge 1;$i--) {
            $old="$path.$i"; $new="$path.$($i+1)"
            if ([IO.File]::Exists($old)) { if ([IO.File]::Exists($new)) {[IO.File]::Delete($new)}; [IO.File]::Move($old,$new) }
        }
        if ([IO.File]::Exists("$path.1")) {[IO.File]::Delete("$path.1")}; [IO.File]::Move($path,"$path.1")
    }
    [IO.File]::AppendAllText($path,('{0:o} {1}{2}' -f [DateTime]::UtcNow,$Message,[Environment]::NewLine),[Text.Encoding]::UTF8)
    Set-PrivatePermissions $path
}
function Read-PackageManifest([string]$Directory) {
    $path=Join-Path $Directory 'PackageManifest.json'
    $m=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($m.PackageVersion -ne $script:Version -or $m.SchemaVersion -ne 1) { throw 'Unsupported package manifest version.' }
    Assert-Properties $m.Files $script:PayloadNames 'Manifest.Files'
    if (@($m.Files.PSObject.Properties).Count -ne $script:PayloadNames.Count) { throw 'Incomplete manifest.' }
    foreach ($name in $script:PayloadNames) {
        $p=Join-Path $Directory $name; Assert-NoReparse $p
        $hash=Get-Property $m.Files $name
        if ($hash -notmatch '^[a-f0-9]{64}$' -or (Get-FileDigest $p) -cne $hash) { throw "File integrity check failed: $name. Reinstall the assigned package." }
    }
    return $m
}
function Get-RegistrySnapshot([string]$Name) {
    if (@($script:PolicyTypes.Keys) -cnotcontains $Name) { throw "Refusing registry name: $Name" }
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $key=$null
    try {
        $key=$base.OpenSubKey($script:RegistryPath,$false)
        if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) { return [pscustomobject]@{Name=$Name;Present=$false;Kind=$null;Value=$null} }
        [pscustomobject]@{Name=$Name;Present=$true;Kind=$key.GetValueKind($Name).ToString();Value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
    } finally { if ($null -ne $key) {$key.Dispose()}; $base.Dispose() }
}
function Set-RegistrySnapshot($Snapshot) {
    if (@($script:PolicyTypes.Keys) -cnotcontains $Snapshot.Name) { throw 'State contains an unsupported registry name.' }
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $key=$null
    try {
        if (-not $Snapshot.Present) {
            $key=$base.OpenSubKey($script:RegistryPath,$true)
            if ($null -ne $key) { $key.DeleteValue($Snapshot.Name,$false) }
            return
        }
        $key=$base.CreateSubKey($script:RegistryPath)
        $v=$Snapshot.Value
        switch ($Snapshot.Kind) {
            DWord {$v=[int]$v}; QWord {$v=[long]$v}
            String {$v=[string]$v}; ExpandString {$v=[string]$v}
            MultiString {$v=[string[]]@($v)}; Binary {$v=[byte[]]@($v)}; None {$v=[byte[]]@($v)}
            default { throw 'Unsupported registry backup type.' }
        }
        $key.SetValue($Snapshot.Name,$v,[Microsoft.Win32.RegistryValueKind]::$($Snapshot.Kind))
    } finally { if ($null -ne $key) {$key.Dispose()}; $base.Dispose() }
}
function Test-SnapshotEqual($Actual,$Desired) {
    if ([bool]$Actual.Present -ne [bool]$Desired.Present) { return $false }
    if (-not $Desired.Present) { return $true }
    if ($Actual.Kind -cne $Desired.Kind) { return $false }
    return ((ConvertTo-Json -InputObject $Actual.Value -Compress -Depth 8) -ceq (ConvertTo-Json -InputObject $Desired.Value -Compress -Depth 8))
}
function Read-ManagerState([string]$Root) {
    $state=Get-Content -LiteralPath (Join-Path $Root 'State.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($state.SchemaVersion -ne 1) { throw 'Unsupported manager state.' }
    foreach ($list in @('Original','LastDesired')) {
        $entries=Get-Property $state $list
        if ($entries -isnot [array]) { throw 'Invalid manager state arrays.' }
        $seen=@{}
        foreach ($entry in $entries) {
            if (@($script:PolicyTypes.Keys) -cnotcontains $entry.Name -or $seen.ContainsKey($entry.Name)) { throw 'Invalid or duplicate registry name in state.' }
            if ($entry.Present -isnot [bool]) { throw 'Invalid registry presence in state.' }
            $seen[$entry.Name]=$true
        }
    }
    return $state
}
function Invoke-PolicyEnforcement([string]$Root,$Config) {
    $state=Read-ManagerState $Root
    $original=@{}; $last=@{}
    foreach ($p in $state.Original) {$original[$p.Name]=$p}
    foreach ($p in $state.LastDesired) {$last[$p.Name]=$p}
    $effective=@(Get-MergedPolicySet @($state.LastDesired) @($Config.Desired))
    foreach ($desired in $effective) {
        if (-not $original.ContainsKey($desired.Name)) { $original[$desired.Name]=Get-RegistrySnapshot $desired.Name }
        $last[$desired.Name]=$desired
    }
    # Persist original state BEFORE touching any policy, including first install and upgrades.
    $state.Original=@($original.Values | Sort-Object Name)
    $state.LastDesired=@($last.Values | Sort-Object Name)
    Write-PrivateJson (Join-Path $Root 'State.json') $state
    $changes=0
    foreach ($desired in $effective) {
        if (-not (Test-SnapshotEqual (Get-RegistrySnapshot $desired.Name) $desired)) {
            Set-RegistrySnapshot $desired
            if (-not (Test-SnapshotEqual (Get-RegistrySnapshot $desired.Name) $desired)) { throw "Registry verification failed: $($desired.Name)" }
            Write-ManagerLog $Root "Repaired $($desired.Name); expected present=$($desired.Present)."
            $changes++
        }
    }
    Write-PrivateJson (Join-Path $Root 'Status.json') ([ordered]@{PackageVersion=$script:Version;ConfigurationId=$Config.ConfigurationId;LastSuccessUtc=[DateTime]::UtcNow.ToString('o');Changes=$changes;ManagedCount=$effective.Count})
    Write-ManagerLog $Root "Enforcement succeeded; configuration=$($Config.ConfigurationId); changes=$changes."
    return $changes
}
function Connect-TaskService { $s=New-Object -ComObject 'Schedule.Service'; $s.Connect(); return $s }
function Get-ManagerTask($Service) {
    try { return $Service.GetFolder('\').GetTask($script:TaskName) }
    catch {
        $exception=$_.Exception
        while ($null -ne $exception) {
            if ($exception.HResult -in @(-2147024894,-2147024893)) {return $null}
            $exception=$exception.InnerException
        }
        throw
    }
}
function Assert-OwnedTask($Task) {
    if ($null -ne $Task -and $Task.Definition.RegistrationInfo.Description -notlike "$($script:TaskMarker)*") { throw 'The task name is already used by an unrelated task.' }
}
function Get-TaskArguments([string]$Root) { '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $Root 'Enforce-Policies.ps1') }
function Get-RegistryEventQuery {
    # Exact key only. 4657 covers values; 4663 adds audited access/delete coverage.
    '<QueryList><Query Id="0" Path="Security"><Select Path="Security">*[System[(EventID=4657 or EventID=4663)]] and *[EventData[Data[@Name=''ObjectName'']=''\REGISTRY\MACHINE\SOFTWARE\Policies\Claude'']]</Select></Query></QueryList>'
}
function Register-ManagerTask($Service,[string]$Root,$Config) {
    $d=$Service.NewTask(0)
    $d.RegistrationInfo.Description="$($script:TaskMarker); version=$script:Version; configuration=$($Config.ConfigurationId)"
    $d.Principal.UserId='S-1-5-18'; $d.Principal.LogonType=5; $d.Principal.RunLevel=1
    $d.Settings.Enabled=$true; $d.Settings.StartWhenAvailable=$true
    $d.Settings.DisallowStartIfOnBatteries=$false; $d.Settings.StopIfGoingOnBatteries=$false
    $d.Settings.RunOnlyIfIdle=$false; $d.Settings.RunOnlyIfNetworkAvailable=$false
    $d.Settings.MultipleInstances=2; $d.Settings.ExecutionTimeLimit='PT5M'
    $d.Settings.RestartInterval='PT1M'; $d.Settings.RestartCount=3; $d.Settings.AllowDemandStart=$true
    $time=$d.Triggers.Create(1)
    $time.StartBoundary=(Get-Date).AddMinutes(1).ToString('s')
    $time.Repetition.Interval="PT$($Config.IntervalMinutes)M"; $time.Repetition.StopAtDurationEnd=$false
    # No repetition Duration: repeats indefinitely.
    if ($Config.RunAtStartup) { $t=$d.Triggers.Create(8); $t.Delay='PT30S' }
    if ($Config.RunAtLogon) { $t=$d.Triggers.Create(9); $t.Delay='PT30S' }
    if ($Config.RunOnRegistryChange) { $t=$d.Triggers.Create(0); $t.Subscription=Get-RegistryEventQuery; $t.Delay='PT5S' }
    $a=$d.Actions.Create(0)
    $a.Path=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $a.Arguments=Get-TaskArguments $Root; $a.WorkingDirectory=$Root
    $sddl='O:SYG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)'
    [void]$Service.GetFolder('\').RegisterTaskDefinition($script:TaskName,$d,22,'SYSTEM',$null,5,$sddl)
}
function Assert-TaskHealthy($Task,[string]$Root,$Config) {
    if ($null -eq $Task -or -not $Task.Enabled) { throw 'Scheduled task is missing or disabled.' }
    $d=$Task.Definition
    if ($d.Principal.UserId -notin @('SYSTEM','NT AUTHORITY\SYSTEM','S-1-5-18') -or $d.Principal.RunLevel -ne 1 -or $d.Principal.LogonType -ne 5) { throw 'Task security principal changed.' }
    if ($d.Actions.Count -ne 1) { throw 'Task action count changed.' }
    $a=$d.Actions.Item(1)
    if ($a.Type -ne 0 -or $a.Path -ine (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -or $a.Arguments -cne (Get-TaskArguments $Root) -or $a.WorkingDirectory -ine $Root) { throw 'Task command changed.' }
    if (-not $d.Settings.Enabled -or -not $d.Settings.StartWhenAvailable -or $d.Settings.DisallowStartIfOnBatteries -or $d.Settings.StopIfGoingOnBatteries -or $d.Settings.RunOnlyIfNetworkAvailable -or $d.Settings.RunOnlyIfIdle -or $d.Settings.MultipleInstances -ne 2) { throw 'Task execution settings changed.' }
    $types=@()
    for ($i=1;$i -le $d.Triggers.Count;$i++) {
        $t=$d.Triggers.Item($i); $types+= [int]$t.Type
        if (-not $t.Enabled) { throw 'Task trigger disabled.' }
        if ($t.EndBoundary) { throw 'Task trigger has an expiration.' }
        if ($t.Type -eq 1) {
            if ([System.Xml.XmlConvert]::ToTimeSpan($t.Repetition.Interval).TotalMinutes -ne $Config.IntervalMinutes -or $t.Repetition.Duration) { throw 'Task interval changed.' }
            if ([DateTime]::Parse($t.StartBoundary) -gt (Get-Date).AddMinutes(5)) { throw 'Task start was moved into the future.' }
        }
        elseif ($t.Type -eq 0) {
            if ($t.Subscription -cne (Get-RegistryEventQuery) -or $t.Delay -ne 'PT5S') { throw 'Registry event subscription changed.' }
        }
        elseif ($t.Type -notin @(8,9) -or $t.Delay -ne 'PT30S') { throw 'Task trigger changed.' }
    }
    $expected=@(1); if ($Config.RunAtStartup) {$expected+=8}; if ($Config.RunAtLogon) {$expected+=9}
    if ($Config.RunOnRegistryChange) {$expected+=0}
    if ((($types | Sort-Object) -join ',') -cne (($expected | Sort-Object) -join ',')) { throw 'Task triggers changed.' }
    $sd=New-Object Security.AccessControl.RawSecurityDescriptor($Task.GetSecurityDescriptor(7))
    if ($sd.Owner.Value -ne 'S-1-5-18' -or $sd.DiscretionaryAcl.Count -ne 2) { throw 'Task permissions changed.' }
    if (($sd.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0) {throw 'Task permissions inherit unexpectedly.'}
    $sids=@()
    foreach ($ace in $sd.DiscretionaryAcl) {
        if ($ace.AceQualifier -ne 'AccessAllowed' -or $ace.SecurityIdentifier.Value -notin @('S-1-5-18','S-1-5-32-544')) { throw 'Task permissions changed.' }
        if (($ace.AccessMask -band 0x10000000) -eq 0 -and ($ace.AccessMask -band 0x001F01FF) -ne 0x001F01FF) {throw 'Task full-control permission is missing.'}
        $sids+=$ace.SecurityIdentifier.Value
    }
    if (@($sids | Select-Object -Unique).Count -ne 2) { throw 'Task permissions incomplete.' }
}
function Assert-InstallationHealthy([string]$Root) {
    Assert-NoReparse (Split-Path $Root -Parent)
    foreach ($item in @(Get-SafeTree $Root)) {
        # Lock file inherits private permissions and may be open during this read-only check.
        if ($item.Name -ne 'Operation.lock') { Assert-PrivatePermissions $item.FullName }
    }
    $m=Read-PackageManifest $Root
    $config=Read-PolicyConfiguration (Join-Path $Root 'PolicyConfig.json')
    if ($m.ConfigurationId -cne $config.ConfigurationId) { throw 'Manifest/configuration mismatch.' }
    $state=Read-ManagerState $Root
    $service=Connect-TaskService
    Assert-TaskHealthy (Get-ManagerTask $service) $Root $config
    if ($config.RunOnRegistryChange) {
        if (-not (Test-RegistryAuditPolicy)) { throw 'Audit Registry success auditing is disabled.' }
        if (-not (Test-RegistryAuditRule)) { throw 'Registry audit rule is missing.' }
    }
    foreach ($desired in @(Get-MergedPolicySet @($state.LastDesired) @($config.Desired))) {
        if (-not (Test-SnapshotEqual (Get-RegistrySnapshot $desired.Name) $desired)) { throw "Policy drift: $($desired.Name)" }
    }
}
function Get-MergedPolicySet([object[]]$Previous,[object[]]$Incoming) {
    $map=@{}
    foreach ($p in $Previous) {$map[$p.Name]=$p}
    foreach ($p in $Incoming) {$map[$p.Name]=$p}
    # Apply new restrictions/values before enforcing explicit removals.
    $map.Values | Sort-Object @{Expression='Present';Descending=$true},Name
}
function Get-UninstallPlan($State,[object[]]$Current,[string]$Mode) {
    $original=@{}; $currentMap=@{}
    foreach ($p in $State.Original) {$original[$p.Name]=$p}
    foreach ($p in $Current) {$currentMap[$p.Name]=$p}
    foreach ($desired in $State.LastDesired) {
        if (-not $original.ContainsKey($desired.Name) -or -not $currentMap.ContainsKey($desired.Name)) {throw 'Incomplete uninstall snapshot.'}
        if ($Mode -eq 'KeepPolicies' -or -not (Test-SnapshotEqual $currentMap[$desired.Name] $desired)) {continue}
        if ($Mode -eq 'RestoreOriginal') { $original[$desired.Name] }
        elseif ($Mode -eq 'RemoveManaged') { [pscustomobject]@{Name=$desired.Name;Present=$false;Kind=$null;Value=$null} }
        else {throw 'Unsupported uninstall mode.'}
    }
}
function Initialize-AuditNative {
    if ('ClaudePolicyNative' -as [type]) {return}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class ClaudePolicyNative {
 [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
 [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public uint Count; public LUID Luid; public uint Attributes; }
 [StructLayout(LayoutKind.Sequential)] struct AUDIT_POLICY_INFORMATION { public Guid Subcategory; public uint Information; public Guid Category; }
 [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr token);
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LookupPrivilegeValue(string s,string n,out LUID l);
 [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr h,bool d,ref TOKEN_PRIVILEGES p,uint l,IntPtr a,IntPtr b);
 [DllImport("advapi32.dll", SetLastError=true)] static extern bool AuditQuerySystemPolicy(ref Guid g,uint n,out IntPtr p);
 [DllImport("advapi32.dll")] static extern void AuditFree(IntPtr p);
 public static void EnableSecurityPrivilege() {
   IntPtr h; if(!OpenProcessToken(GetCurrentProcess(),0x28,out h)) throw new Win32Exception();
   try { LUID l; if(!LookupPrivilegeValue(null,"SeSecurityPrivilege",out l)) throw new Win32Exception();
     TOKEN_PRIVILEGES p=new TOKEN_PRIVILEGES {Count=1,Luid=l,Attributes=2};
     if(!AdjustTokenPrivileges(h,false,ref p,0,IntPtr.Zero,IntPtr.Zero)) throw new Win32Exception();
     int err=Marshal.GetLastWin32Error(); if(err!=0) throw new Win32Exception(err);
   } finally {CloseHandle(h);}
 }
 public static bool RegistryAuditSuccess() {
   Guid g=new Guid("0CCE921E-69AE-11D9-BED3-505054503030"); IntPtr p;
   if(!AuditQuerySystemPolicy(ref g,1,out p)) throw new Win32Exception();
   try {var a=(AUDIT_POLICY_INFORMATION)Marshal.PtrToStructure(p,typeof(AUDIT_POLICY_INFORMATION)); return (a.Information & 1)!=0;}
   finally {AuditFree(p);}
 }
}
'@
    [ClaudePolicyNative]::EnableSecurityPrivilege()
}
function Test-RegistryAuditPolicy { Initialize-AuditNative; [ClaudePolicyNative]::RegistryAuditSuccess() }
function Open-AuditRegistryKey {
    Initialize-AuditNative
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    try {
        # READ_CONTROL + ACCESS_SYSTEM_SECURITY: read/write the SACL only.
        return $base.OpenSubKey($script:RegistryPath,[Microsoft.Win32.RegistryKeyPermissionCheck]::Default,[Security.AccessControl.RegistryRights]0x01020000)
    } finally {$base.Dispose()}
}
function Get-AuditSnapshot {
    $key=Open-AuditRegistryKey
    if ($null -eq $key) {return $null}
    try {
        $acl=$key.GetAccessControl([Security.AccessControl.AccessControlSections]::Audit)
        [pscustomobject]@{Binary=[Convert]::ToBase64String($acl.GetSecurityDescriptorBinaryForm());Sddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Audit)}
    } finally {$key.Dispose()}
}
function Set-AuditSnapshot($Snapshot) {
    if ($null -eq $Snapshot) {return}
    $key=Open-AuditRegistryKey
    if ($null -eq $key) {return}
    try {
        $acl=New-Object Security.AccessControl.RegistrySecurity
        $acl.SetSecurityDescriptorBinaryForm([Convert]::FromBase64String($Snapshot.Binary),[Security.AccessControl.AccessControlSections]::Audit)
        $key.SetAccessControl($acl)
    } finally {$key.Dispose()}
}
function Test-AuditRuleInAcl($Acl) {
    $rights=[Security.AccessControl.RegistryRights]::SetValue -bor [Security.AccessControl.RegistryRights]::Delete
    foreach ($rule in $Acl.GetAuditRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.IdentityReference.Value -eq 'S-1-1-0' -and ($rule.AuditFlags -band [Security.AccessControl.AuditFlags]::Success) -ne 0 -and ($rule.RegistryRights -band $rights) -eq $rights) {return $true}
    }
    return $false
}
function Test-RegistryAuditRule {
    $key=Open-AuditRegistryKey
    if ($null -eq $key) {return $false}
    try { Test-AuditRuleInAcl ($key.GetAccessControl([Security.AccessControl.AccessControlSections]::Audit)) }
    finally {$key.Dispose()}
}
function Ensure-RegistryAuditing([string]$Root,$Config,[switch]$Install) {
    if (-not $Config.RunOnRegistryChange) { return }
    if ($Install -and $Config.ConfigureAuditPolicy) {
        $output=& (Join-Path $env:SystemRoot 'System32\auditpol.exe') /set '/subcategory:{0CCE921E-69AE-11D9-BED3-505054503030}' /success:enable 2>&1
        if ($LASTEXITCODE -ne 0) {throw "Unable to enable Audit Registry success auditing: $output"}
    }
    if (-not (Test-RegistryAuditPolicy)) {throw 'Audit Registry success auditing is disabled. Enable it centrally or set ConfigureAuditPolicy=true.'}
    # Ensure an audit target even for a configuration containing only explicit removals.
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    try {$key=$base.CreateSubKey($script:RegistryPath); $key.Dispose()} finally {$base.Dispose()}
    $key=Open-AuditRegistryKey
    try {
        $acl=$key.GetAccessControl([Security.AccessControl.AccessControlSections]::Audit)
        if (Test-AuditRuleInAcl $acl) {return}
        $before=[pscustomobject]@{Binary=[Convert]::ToBase64String($acl.GetSecurityDescriptorBinaryForm());Sddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Audit)}
        $sid=New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
        $rights=[Security.AccessControl.RegistryRights]::SetValue -bor [Security.AccessControl.RegistryRights]::Delete
        $rule=New-Object Security.AccessControl.RegistryAuditRule($sid,$rights,[Security.AccessControl.InheritanceFlags]::None,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AuditFlags]::Success)
        $acl.AddAuditRule($rule)
        $state=Read-ManagerState $Root
        $state | Add-Member -NotePropertyName Audit -NotePropertyValue ([pscustomobject]@{Original=$before;ExpectedSddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Audit)}) -Force
        Write-PrivateJson (Join-Path $Root 'State.json') $state
        $key.SetAccessControl($acl)
    } finally {$key.Dispose()}
}
function Restore-ManagerAudit([string]$Root) {
    $state=Read-ManagerState $Root
    $audit=Get-Property $state 'Audit'
    if ($null -eq $audit) {return}
    $current=Get-AuditSnapshot
    if ($null -ne $current -and $current.Sddl -ceq $audit.ExpectedSddl) {Set-AuditSnapshot $audit.Original}
    elseif ($null -ne $current) {Write-ManagerLog $Root 'SACL changed externally; leaving its audit entries in place.'}
    $state.PSObject.Properties.Remove('Audit')
    Write-PrivateJson (Join-Path $Root 'State.json') $state
    # Audit Registry is a shared machine setting. Never disable it on uninstall.
}
Export-ModuleMember -Function *
