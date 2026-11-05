# Windows PowerShell 5.1 compatible. No UI is loaded by this file.
Set-StrictMode -Version 2.0

function Add-SetupLogLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    # One writer at a time, including the UI and the step worker. Retry contention.
    $bytes = [Text.Encoding]::UTF8.GetBytes($Line + [Environment]::NewLine)
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        $stream = $null
        try {
            $stream = [IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $stream.Write($bytes, 0, $bytes.Length)
            return
        }
        catch [IO.IOException] {
            if ($attempt -eq 49) { throw }
            Start-Sleep -Milliseconds 100
        }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
    }
}

function New-SetupDirectorySecurity {
    param([string[]]$ReaderSids = @(), [switch]$InheritReaderAccess)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $account = [Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($account, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    foreach ($sid in @($ReaderSids | Sort-Object -Unique)) {
        if ($sid -in @('S-1-5-18','S-1-5-32-544')) { continue }
        $account = [Security.Principal.SecurityIdentifier]::new($sid)
        $inheritance = [Security.AccessControl.InheritanceFlags]::None
        if ($InheritReaderAccess) { $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' }
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($account, 'ReadAndExecute', $inheritance, 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    return $acl
}

function Set-SetupDirectorySecurity {
    param([Parameter(Mandatory)][string]$Path, [string[]]$ReaderSids = @(), [switch]$InheritReaderAccess)
    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a real directory, not a link: $Path"
    }
    $acl = New-SetupDirectorySecurity -ReaderSids $ReaderSids -InheritReaderAccess:$InheritReaderAccess
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Get-SetupLogUserSid {
    $sessionId = (Get-Process -Id $PID).SessionId
    if ($sessionId -eq 0) { throw 'No interactive setup session; specify Behavior.LogReaderSids for log access from session 0.' }
    $owners = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | ForEach-Object {
        if ($_.SessionId -eq $sessionId) {
            $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop
            if ($owner.ReturnValue -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$owner.Sid) -and $owner.Sid -notin @('S-1-5-18','S-1-5-19','S-1-5-20')) {
                ([Security.Principal.SecurityIdentifier]::new([string]$owner.Sid)).Value
            }
        }
    } | Sort-Object -Unique)
    if ($owners.Count -ne 1) { throw "Could not identify one Explorer owner in session $sessionId for log read access." }
    return [string]$owners[0]
}

function Add-SetupLogReaderAccess {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ReaderSid, [switch]$InheritReaderAccess)
    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a real directory, not a link: $Path"
    }
    $account = [Security.Principal.SecurityIdentifier]::new($ReaderSid)
    $inheritance = [Security.AccessControl.InheritanceFlags]::None
    if ($InheritReaderAccess) { $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' }
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($account, 'ReadAndExecute', $inheritance, 'None', 'Allow')
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Import-SetupStepViewModel {
    param([Parameter(Mandatory)][string]$Path)
    # Do not reuse DeviceSetupUI.StepViewModel from an earlier run in ISE/a
    # persistent PowerShell host. Each source revision gets its own CLR name.
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
    $namespacePattern = [regex]'\bnamespace\s+DeviceSetupUI\s*\{'
    if (-not $namespacePattern.IsMatch($source)) {
        throw "UI/StepViewModel.cs has an unexpected namespace. Replace it with the file from the same release as Start-DeviceSetup.ps1."
    }
    $namespace = 'DeviceSetupUI_Model_' + (Get-SetupHash $source)
    $typeName = $namespace + '.StepViewModel'
    $modelType = $typeName -as [type]
    if ($null -eq $modelType) {
        $compiledSource = $namespacePattern.Replace($source, ('namespace ' + $namespace + ' {'), 1)
        Add-Type -TypeDefinition $compiledSource -Language CSharp -ErrorAction Stop
        $modelType = $typeName -as [type]
    }
    foreach ($name in @('IsSelected','ShowSelection','SelectStepLabel')) {
        $property = $modelType.GetProperty($name)
        if ($null -eq $property -or -not $property.CanRead -or -not $property.CanWrite) {
            throw "UI file version mismatch: UI/StepViewModel.cs is missing writable property '$name'. Copy UI/StepViewModel.cs and UI/MainWindow.xaml from the same release as Start-DeviceSetup.ps1 and Core/Setup.Common.ps1, then launch again. Your JSON does not need an IsSelected setting."
        }
    }
    return $modelType
}

function Set-SetupXamlTheme {
    param([Parameter(Mandatory)][xml]$Xaml, [Parameter(Mandatory)]$Appearance)
    # Apply colors before XamlReader.Load. WPF must create the actual Brush objects.
    # Inserting New-Object output into ResourceDictionary's object-valued indexer can
    # preserve a PowerShell wrapper that WPF cannot use as a Background/Foreground.
    $palette = @{}
    if ($Appearance.Theme -eq 'Dark') {
        $palette = @{ CanvasBrush='#151C29'; CardBrush='#1E293B'; TextBrush='#F1F5F9'; MutedBrush='#ACBAD0'; BorderBrush='#35435A'; SubtleBrush='#263349'; AccentSoftBrush='#243A61' }
    }
    $palette.AccentBrush = $Appearance.AccentColor
    $palette.SuccessBrush = $Appearance.SuccessColor
    $palette.FailureBrush = $Appearance.FailureColor
    $palette.WarningBrush = $Appearance.WarningColor
    $namespaces = [System.Xml.XmlNamespaceManager]::new($Xaml.NameTable)
    $namespaces.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $namespaces.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    foreach ($key in $palette.Keys) {
        $brushNode = $Xaml.SelectSingleNode("/w:Window/w:Window.Resources/w:SolidColorBrush[@x:Key='$key']", $namespaces)
        if ($null -eq $brushNode) { throw "Missing SolidColorBrush resource in MainWindow.xaml: $key" }
        $brushNode.SetAttribute('Color', [string]$palette[$key])
    }
}

function Get-SetupHash {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Resolve-SetupContentPath {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $null }
    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "Use a package-relative path, not an absolute path: $RelativePath"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $path = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the package: $RelativePath"
    }
    return $path
}

function Assert-SetupProperties {
    param($Object, [string[]]$Names, [string]$Location)
    if ($null -eq $Object) { throw "Missing object: $Location" }
    foreach ($name in $Names) {
        if ($null -eq $Object.PSObject.Properties[$name]) { throw "Missing setting: $Location.$name" }
    }
}

function Read-SetupConfiguration {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$PackageRoot)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Configuration not found: $Path" }
    $cfg = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Assert-SetupProperties $cfg @('SchemaVersion','SetupId','SetupVersion','Branding','Appearance','Text','Behavior','Steps') 'Config'
    if ($cfg.SchemaVersion -ne 1) { throw 'SchemaVersion must be 1.' }
    if ($cfg.SetupId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { throw 'SetupId must be 1-80 letters, digits, periods, underscores, or hyphens.' }
    if ($cfg.SetupVersion -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$') { throw 'SetupVersion must be a safe 1-40 character version string.' }
    Assert-SetupProperties $cfg.Branding @('CompanyName','WindowTitle','Heading','Message','LogoPath','BannerPath','BannerHeight','LogoMaxWidth','LogoMaxHeight') 'Branding'
    # Optional since hotfix 3. Older configurations receive the fitting defaults
    # in memory so existing customer configuration files do not need replacing.
    $brandingDefaults = @{ BannerStretch='Uniform'; BannerStretchDirection='DownOnly'; IconPath='' }
    foreach ($name in $brandingDefaults.Keys) {
        if ($null -eq $cfg.Branding.PSObject.Properties[$name]) {
            $cfg.Branding | Add-Member -MemberType NoteProperty -Name $name -Value $brandingDefaults[$name]
        }
    }
    if ($cfg.Branding.BannerStretch -notin @('Uniform','UniformToFill','None','Fill')) { throw 'Branding.BannerStretch must be Uniform, UniformToFill, None, or Fill.' }
    if ($cfg.Branding.BannerStretchDirection -notin @('DownOnly','Both','UpOnly')) { throw 'Branding.BannerStretchDirection must be DownOnly, Both, or UpOnly.' }
    Assert-SetupProperties $cfg.Appearance @('Theme','AccentColor','SuccessColor','FailureColor','WarningColor','WindowWidth','WindowHeight','Topmost','ReduceMotion','ShowElapsedTime','ShowStepNumbers','FontFamily') 'Appearance'
    Assert-SetupProperties $cfg.Text @('RunningHeading','RunningMessage','SuccessHeading','SuccessMessage','WarningHeading','WarningMessage','FailureHeading','FailureMessage','Footer','Support','RetryButton','CloseButton','CopyButton','DetailsLabel') 'Text'
    $selectionText = @{
        SelectionHeading='Choose optional apps'; SelectionMessage='Select any extras you would like, then start setup. Required setup runs automatically.'
        StartButton='Start setup'; SelectionFooter='Optional apps are unchecked by default.'; SelectStepLabel='Include this optional step'
    }
    foreach ($name in $selectionText.Keys) {
        if ($null -eq $cfg.Text.PSObject.Properties[$name]) { $cfg.Text | Add-Member -MemberType NoteProperty -Name $name -Value $selectionText[$name] }
        if ($cfg.Text.$name -isnot [string]) { throw "Text.$name must be a string." }
    }
    Assert-SetupProperties $cfg.Behavior @('RequireSystemForLive','ResumeCompletedSteps','StopOnRequiredFailure','AllowRetry','AutoCloseSuccessSeconds','PollIntervalMilliseconds','StateDirectory') 'Behavior'
    if ($null -eq $cfg.Behavior.PSObject.Properties['AllowInteractiveUserToReadLogs']) {
        $cfg.Behavior | Add-Member -MemberType NoteProperty -Name AllowInteractiveUserToReadLogs -Value $true
    }
    if ($null -eq $cfg.Behavior.PSObject.Properties['LogReaderSids']) {
        $cfg.Behavior | Add-Member -MemberType NoteProperty -Name LogReaderSids -Value @()
    }
    if ($cfg.Behavior.AllowInteractiveUserToReadLogs -isnot [bool]) { throw 'Behavior.AllowInteractiveUserToReadLogs must be a JSON boolean.' }
    if ($cfg.Behavior.LogReaderSids -isnot [Array]) { throw 'Behavior.LogReaderSids must be a JSON array of user/group SID strings.' }
    foreach ($readerSid in $cfg.Behavior.LogReaderSids) {
        if ($readerSid -isnot [string] -or $readerSid -notmatch '^S-1-\d+(?:-\d+)+$') { throw 'Behavior.LogReaderSids must contain only SID strings.' }
        try { $null = [Security.Principal.SecurityIdentifier]::new($readerSid) }
        catch { throw "Behavior.LogReaderSids contains an invalid SID: $readerSid" }
    }
    if ($cfg.Appearance.Theme -notin @('Light','Dark')) { throw 'Appearance.Theme must be Light or Dark.' }
    foreach ($color in @('AccentColor','SuccessColor','FailureColor','WarningColor')) {
        if ($cfg.Appearance.$color -notmatch '^#[0-9a-fA-F]{6}$') { throw "Appearance.$color must be #RRGGBB." }
    }
    foreach ($pair in @(@($cfg.Appearance,'Topmost'),@($cfg.Appearance,'ReduceMotion'),@($cfg.Appearance,'ShowElapsedTime'),@($cfg.Appearance,'ShowStepNumbers'),@($cfg.Behavior,'RequireSystemForLive'),@($cfg.Behavior,'ResumeCompletedSteps'),@($cfg.Behavior,'StopOnRequiredFailure'),@($cfg.Behavior,'AllowRetry'))) {
        if ($pair[0].($pair[1]) -isnot [bool]) { throw "$($pair[1]) must be a JSON boolean." }
    }
    foreach ($range in @(
        @('WindowWidth',$cfg.Appearance.WindowWidth,640,1600),
        @('WindowHeight',$cfg.Appearance.WindowHeight,520,1200),
        @('BannerHeight',$cfg.Branding.BannerHeight,40,240),
        @('LogoMaxWidth',$cfg.Branding.LogoMaxWidth,24,400),
        @('LogoMaxHeight',$cfg.Branding.LogoMaxHeight,24,120),
        @('PollIntervalMilliseconds',$cfg.Behavior.PollIntervalMilliseconds,200,2000),
        @('AutoCloseSuccessSeconds',$cfg.Behavior.AutoCloseSuccessSeconds,0,3600)
    )) {
        if ($range[1] -is [string] -or $range[1] -is [bool] -or $range[1] -isnot [ValueType] -or $range[1] -lt $range[2] -or $range[1] -gt $range[3]) {
            throw "$($range[0]) must be a number between $($range[2]) and $($range[3])."
        }
    }
    foreach ($field in @('LogoPath','BannerPath')) {
        $p = Resolve-SetupContentPath $PackageRoot $cfg.Branding.$field
        if ($p) {
            if ([IO.Path]::GetExtension($p) -notin @('.png','.jpg','.jpeg','.bmp')) { throw "$field supports PNG, JPG, or BMP." }
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Branding image not found: $p" }
        }
    }
    if ($cfg.Branding.IconPath -isnot [string]) { throw 'Branding.IconPath must be a string.' }
    $iconPath = Resolve-SetupContentPath $PackageRoot $cfg.Branding.IconPath
    if ($iconPath) {
        if ([IO.Path]::GetExtension($iconPath) -notin @('.ico','.png')) { throw 'IconPath supports ICO or PNG.' }
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { throw "Window icon not found: $iconPath" }
    }
    if (@($cfg.Steps).Count -lt 1 -or @($cfg.Steps).Count -gt 10) { throw 'Configure between 1 and 10 steps total.' }
    $ids = @{}
    $enabledBefore = @{}
    $enabledCount = 0
    foreach ($step in $cfg.Steps) {
        Assert-SetupProperties $step @('Id','Enabled','Title','Description','Script','Parameters','TimeoutSeconds','SuccessExitCodes','RebootExitCodes','Required','DependsOn','DemoSeconds','DemoFailFirstAttempt') 'Steps[]'
        if ($null -eq $step.PSObject.Properties['UserSelectable']) { $step | Add-Member -MemberType NoteProperty -Name UserSelectable -Value $false }
        if ($step.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$') { throw "Invalid step Id: $($step.Id)" }
        if ($ids.ContainsKey($step.Id)) { throw "Duplicate step Id: $($step.Id)" }
        $ids[$step.Id] = $true
        foreach ($flag in @('Enabled','Required','DemoFailFirstAttempt','UserSelectable')) {
            if ($step.$flag -isnot [bool]) { throw "Step $($step.Id): $flag must be a JSON boolean." }
        }
        if ($step.UserSelectable -and $step.Required) { throw "Step $($step.Id): UserSelectable requires Required=false." }
        if ([string]::IsNullOrWhiteSpace($step.Title)) { throw "Step $($step.Id) requires a Title." }
        if ($step.Parameters -isnot [pscustomobject]) { throw "Step $($step.Id): Parameters must be a JSON object." }
        if ($step.TimeoutSeconds -is [string] -or $step.TimeoutSeconds -is [bool] -or $step.TimeoutSeconds -lt 1 -or $step.TimeoutSeconds -gt 86400) { throw "Step $($step.Id): TimeoutSeconds must be 1-86400." }
        if ($step.DemoSeconds -is [string] -or $step.DemoSeconds -is [bool] -or $step.DemoSeconds -lt 1 -or $step.DemoSeconds -gt 60) { throw "Step $($step.Id): DemoSeconds must be 1-60." }
        if (@($step.SuccessExitCodes).Count -lt 1) { throw "Step $($step.Id): SuccessExitCodes cannot be empty." }
        foreach ($code in @($step.SuccessExitCodes) + @($step.RebootExitCodes)) {
            if ($code -isnot [int] -and $code -isnot [long]) { throw "Step $($step.Id): exit codes must be integers." }
        }
        foreach ($code in $step.RebootExitCodes) {
            if ($code -notin $step.SuccessExitCodes) { throw "Step $($step.Id): every RebootExitCode must also be a SuccessExitCode." }
        }
        $scriptPath = Resolve-SetupContentPath $PackageRoot $step.Script
        if (-not $scriptPath -or [IO.Path]::GetExtension($scriptPath) -ne '.ps1') { throw "Step $($step.Id) requires a relative .ps1 Script path." }
        if ($step.Enabled) {
            $enabledCount++
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Step script not found: $scriptPath" }
            foreach ($dependency in @($step.DependsOn)) {
                if (-not $enabledBefore.ContainsKey([string]$dependency)) { throw "Step $($step.Id): dependency '$dependency' must be an earlier enabled step." }
                if (-not $step.UserSelectable -and $enabledBefore[[string]$dependency].UserSelectable) { throw "Step $($step.Id): an automatic step cannot depend on user-selectable step '$dependency'." }
            }
            $enabledBefore[$step.Id] = $step
        }
    }
    if ($enabledCount -eq 0) { throw 'Enable at least one step.' }
    return $cfg
}

function Write-SetupJson {
    param([string]$Path, $Value)
    $json = $Value | ConvertTo-Json -Depth 20
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    try {
        for ($attempt = 0; $attempt -lt 8; $attempt++) {
            try {
                # PowerShell coerces $null to an empty string for this .NET string
                # parameter. NullString supplies a true null: no backup filename.
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
                else { [IO.File]::Move($temp, $Path) }
                break
            }
            catch [IO.IOException] {
                if ($attempt -eq 7) { throw }
                # A reader can briefly hold a handle without delete sharing.
                Start-Sleep -Milliseconds 25
            }
        }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Get-SetupStepFingerprint {
    param($Step, [string]$PackageRoot)
    $path = Resolve-SetupContentPath $PackageRoot $Step.Script
    $execution = [ordered]@{
        Script = $Step.Script
        ScriptHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Parameters = $Step.Parameters
        SuccessExitCodes = $Step.SuccessExitCodes
        RebootExitCodes = $Step.RebootExitCodes
        DependsOn = $Step.DependsOn
    }
    return Get-SetupHash ($execution | ConvertTo-Json -Depth 15 -Compress)
}

function Get-SetupOutcome {
    param([object[]]$Items)
    $incompleteRequired = @($Items | Where-Object { $_.Definition.Required -and $_.Status -notin @('Complete','AlreadyComplete') })
    $issues = @($Items | Where-Object { $_.Status -in @('Failed','Skipped') })
    if ($incompleteRequired.Count -gt 0) { return 'Failed' }
    if ($issues.Count -gt 0) { return 'Warning' }
    return 'Success'
}

function Get-SetupResumeStatus {
    param($Step, [string]$Fingerprint, $State, [switch]$ChooseOptional)
    if ($State.Completed.ContainsKey($Step.Id) -and $State.Completed[$Step.Id].Fingerprint -eq $Fingerprint) { return 'AlreadyComplete' }
    if ($Step.UserSelectable -and -not $ChooseOptional -and $State.Declined.ContainsKey($Step.Id) -and $State.Declined[$Step.Id].Fingerprint -eq $Fingerprint) { return 'NotSelected' }
    return 'Pending'
}

function Get-SetupSelectionBlock {
    param([object[]]$Items)
    foreach ($item in $Items) {
        if ($item.Status -ne 'Pending' -or -not $item.View.IsSelected) { continue }
        foreach ($id in @($item.Definition.DependsOn)) {
            $dependency = @($Items | Where-Object { $_.Definition.Id -eq $id })
            if ($dependency.Count -ne 1) { return "Missing prerequisite for $($item.Definition.Title): $id" }
            if ($dependency[0].Status -in @('Complete','AlreadyComplete')) { continue }
            if (-not $dependency[0].View.IsSelected) { return "Select '$($dependency[0].Definition.Title)' to include '$($item.Definition.Title)', or uncheck '$($item.Definition.Title)'." }
        }
    }
    return $null
}

function Set-SetupStepSelection {
    param([object[]]$Items)
    $block = Get-SetupSelectionBlock -Items $Items
    if ($block) { throw $block }
    foreach ($item in $Items) {
        $item.View.ShowSelection = $false
        if ($item.Status -eq 'Pending' -and $item.Definition.UserSelectable -and -not $item.View.IsSelected) {
            $item.Status = 'NotSelected'
            $item.View.Status = 'NotSelected'
            $item.View.Detail = 'Not selected for installation'
        }
    }
}

function Get-SetupDependencyBlock {
    param($Item, [object[]]$Items)
    foreach ($id in @($Item.Definition.DependsOn)) {
        $dependency = @($Items | Where-Object { $_.Definition.Id -eq $id })
        if ($dependency.Count -ne 1 -or $dependency[0].Status -notin @('Complete','AlreadyComplete')) {
            return "Waiting for successful completion of: $id"
        }
    }
    return $null
}
