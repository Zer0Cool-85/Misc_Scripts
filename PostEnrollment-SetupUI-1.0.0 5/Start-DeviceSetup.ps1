#Requires -Version 5.1
<#
Standalone WPF front end. Keep using your existing SYSTEM + ServiceUI launcher.
No parameters => safe demo. Production execution requires the explicit -Live switch.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Config/Setup.json'),
    [switch]$Demo,
    [switch]$Live,
    [switch]$ValidateOnly,
    [switch]$ResetState,
    [switch]$ChooseOptional
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core/Setup.Common.ps1')
$script:packageRoot = $PSScriptRoot
try { $script:config = Read-SetupConfiguration -Path $ConfigPath -PackageRoot $PSScriptRoot }
catch {
    if (-not $ValidateOnly -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName PresentationFramework
        [Windows.MessageBox]::Show($_.Exception.Message, 'Device Setup configuration error', 'OK', 'Error') | Out-Null
    }
    throw
}
if ($ValidateOnly) {
    Write-Output "VALID: $($script:config.SetupId), $(@($script:config.Steps | Where-Object Enabled).Count) enabled step(s)."
    exit 0
}
if ($Demo -and $Live) { throw 'Choose -Demo or -Live, not both.' }
$script:isDemo = -not $Live
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'The WPF window requires Windows.' }
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use 64-bit Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.' }
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell. From a 32-bit caller, use Sysnative.' }
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Launch powershell.exe with -STA.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($Live -and $script:config.Behavior.RequireSystemForLive -and $identity.User.Value -ne 'S-1-5-18') {
    throw 'Live mode requires SYSTEM. Use your existing SYSTEM + ServiceUI launcher. Demo mode does not require elevation.'
}

Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
try { $script:stepViewModelType = Import-SetupStepViewModel -Path (Join-Path $PSScriptRoot 'UI/StepViewModel.cs') }
catch {
    [Windows.MessageBox]::Show($_.Exception.Message, 'Device Setup UI files could not load', 'OK', 'Error') | Out-Null
    throw
}
if (-not ('DeviceSetupUI.TaskbarIdentity' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'UI/TaskbarIdentity.cs') }
$script:mutex = $null
$script:hasMutex = $false
$script:timer = $null
$script:exitCode = 1
$script:engineFailure = ''
$script:timeoutOccurred = $false
$script:activeItem = $null
$script:busy = $true
$script:runFinishedAt = $null
$script:rebootRequired = $false
$script:bootStamp = ''
$script:items = @()
$script:ui = @{}
$script:runClock = New-Object Diagnostics.Stopwatch
$script:awaitingSelection = $false
$script:hasStarted = $false

function Write-RunLog {
    param([string]$Message)
    $line = '{0} {1}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'), $Message
    Add-SetupLogLine -Path (Join-Path $script:runDirectory 'SetupUI.log') -Line $line
}

function Set-ItemState {
    param($Item, [string]$Status, [string]$Detail, [string]$ErrorText = '')
    $Item.Status = $Status
    $Item.View.Status = $Status
    $Item.View.Detail = $Detail
    $Item.View.Error = $ErrorText
    $Item.View.RefreshProgress()
    Write-RunLog "$($Item.Definition.Id): $Status - $Detail"
}

function Get-ClockText {
    param([TimeSpan]$Span)
    if ($Span.TotalHours -ge 1) { return '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($Span.TotalHours), $Span.Minutes, $Span.Seconds }
    return '{0:00}:{1:00}' -f [int][Math]::Floor($Span.TotalMinutes), $Span.Seconds
}

function Update-OverallProgress {
    $included = @($script:items | Where-Object { $_.Status -ne 'NotSelected' })
    $finished = @($included | Where-Object { $_.Status -notin @('Pending','Running') }).Count
    $partial = 0.0
    if ($null -ne $script:activeItem -and $script:activeItem.View.Percent -ge 0) { $partial = $script:activeItem.View.Percent / 100.0 }
    if ($included.Count -eq 0) { $script:ui.OverallProgress.Value = 100 }
    else { $script:ui.OverallProgress.Value = 100.0 * ($finished + $partial) / $included.Count }
    $script:ui.ProgressCount.Text = "$finished of $($included.Count) included steps finished"
    $script:ui.ElapsedText.Text = 'Elapsed ' + (Get-ClockText $script:runClock.Elapsed)
}

function Save-RunReport {
    $report = [ordered]@{
        SetupId = $script:config.SetupId; SetupVersion = $script:config.SetupVersion
        Demo = $script:isDemo; Identity = $identity.Name; FinishedUtc = [DateTime]::UtcNow.ToString('o')
        Outcome = (Get-SetupOutcome $script:items); ExitCode = $script:exitCode
        RebootRequired = $script:rebootRequired; EngineError = $script:engineFailure
        Steps = @($script:items | ForEach-Object { [ordered]@{
            Id = $_.Definition.Id; Title = $_.Definition.Title; Required = $_.Definition.Required
            UserSelectable = $_.Definition.UserSelectable; Selected = $_.View.IsSelected
            Status = $_.Status; Attempts = $_.Attempt; ExitCode = $_.FinalExitCode
            Detail = $_.View.Detail; Error = $_.View.Error; LogPath = $_.LogPath
        } })
    }
    Write-SetupJson -Path (Join-Path $script:runDirectory 'Results.json') -Value $report
}

function Finish-SetupRun {
    $script:busy = $false
    $script:runFinishedAt = [DateTime]::Now
    $script:runClock.Stop()
    $outcome = Get-SetupOutcome $script:items
    if ($script:engineFailure) { $outcome = 'Failed' }
    if ($outcome -eq 'Failed') {
        $script:exitCode = 1
        $script:ui.OverallHeading.Text = $script:config.Text.FailureHeading
        $script:ui.OverallMessage.Text = $script:config.Text.FailureMessage
        $script:ui.OverallProgress.Foreground = $script:window.Resources['FailureBrush']
    }
    elseif ($outcome -eq 'Warning') {
        $script:exitCode = 0
        $script:ui.OverallHeading.Text = $script:config.Text.WarningHeading
        $script:ui.OverallMessage.Text = $script:config.Text.WarningMessage
        $script:ui.OverallProgress.Foreground = $script:window.Resources['WarningBrush']
    }
    else {
        $script:exitCode = 0
        $script:ui.OverallHeading.Text = $script:config.Text.SuccessHeading
        $script:ui.OverallMessage.Text = $script:config.Text.SuccessMessage
        $script:ui.OverallProgress.Foreground = $script:window.Resources['SuccessBrush']
    }
    if ($script:rebootRequired) {
        $script:ui.RebootMessage.Visibility = 'Visible'
        if ($script:exitCode -eq 0) { $script:exitCode = 3010 }
    }
    $script:ui.CloseButton.IsEnabled = $true
    $script:ui.CloseButton.Content = $script:config.Text.CloseButton
    $script:ui.RetryButton.Visibility = 'Collapsed'
    if ($script:config.Behavior.AllowRetry -and -not $script:timeoutOccurred -and -not $script:engineFailure -and @($script:items | Where-Object { $_.Status -in @('Failed','Skipped') }).Count -gt 0) {
        $script:ui.RetryButton.Visibility = 'Visible'
    }
    Update-OverallProgress
    Save-RunReport
    Write-RunLog "Run finished: $outcome; exit code $script:exitCode"
}

function Start-SetupWorkflow {
    if ($script:hasStarted) { return }
    $block = Get-SetupSelectionBlock -Items $script:items
    if ($block) {
        $script:ui.OverallMessage.Text = $block
        return
    }
    Set-SetupStepSelection -Items $script:items
    $script:hasStarted = $true
    $script:awaitingSelection = $false
    foreach ($item in $script:items) {
        if ($item.Definition.UserSelectable) {
            if ($item.Status -eq 'NotSelected') {
                $script:state.Declined[$item.Definition.Id] = [ordered]@{ Fingerprint=$item.Fingerprint; DeclinedUtc=[DateTime]::UtcNow.ToString('o') }
            }
            elseif ($item.Status -eq 'Pending') { $script:state.Declined.Remove($item.Definition.Id) }
        }
        Write-RunLog "$($item.Definition.Id): choice recorded; selected=$($item.View.IsSelected); status=$($item.Status)"
    }
    if (-not $script:isDemo -and $script:config.Behavior.ResumeCompletedSteps) {
        Write-SetupJson -Path $script:statePath -Value $script:state
    }
    $script:ui.CloseButton.IsEnabled = $false
    $script:ui.CloseButton.Content = $script:config.Text.CloseButton
    $script:ui.OverallHeading.Text = $script:config.Text.RunningHeading
    $script:ui.OverallMessage.Text = $script:config.Text.RunningMessage
    $script:ui.FooterText.Text = $script:config.Text.Footer
    $script:runClock.Start()
    Start-NextStep
    $script:timer.Start()
}

function Complete-ActiveStep {
    param([int]$Code, [string]$ErrorText = '')
    $item = $script:activeItem
    $item.Clock.Stop()
    $item.FinalExitCode = $Code
    $item.View.Percent = -1
    if ($Code -in $item.Definition.SuccessExitCodes -and -not $item.TimedOut) {
        $reboot = $Code -in $item.Definition.RebootExitCodes
        if ($reboot) { $script:rebootRequired = $true }
        $detail = 'Completed successfully'
        if ($reboot) { $detail = 'Completed; restart required' }
        Set-ItemState $item 'Complete' $detail
        if (-not $script:isDemo -and $script:config.Behavior.ResumeCompletedSteps) {
            $script:state.Completed[$item.Definition.Id] = [ordered]@{
                Fingerprint = $item.Fingerprint; CompletedUtc = [DateTime]::UtcNow.ToString('o')
                RebootRequired = $reboot; BootStamp = $script:bootStamp
            }
            try { Write-SetupJson -Path $script:statePath -Value $script:state }
            catch {
                # Failure to persist must be visible; a later launch could re-run the work.
                $script:engineFailure = 'Could not save completion state: ' + $_.Exception.Message
                Set-ItemState $item 'Failed' 'Setup finished, but its completion record could not be saved.' $script:engineFailure
            }
        }
    }
    else {
        if (-not $ErrorText) { $ErrorText = "Step exited with code $Code. See its transcript for details: $($item.LogPath)" }
        $detail = "Needs attention (exit $Code)"
        if ($item.TimedOut) { $detail = 'Time limit exceeded; this run has stopped.' }
        Set-ItemState $item 'Failed' $detail $ErrorText
    }
    if ($script:config.Appearance.ShowElapsedTime) { $item.View.Elapsed = Get-ClockText $item.Clock.Elapsed }
    if ($item.Process) { $item.Process.Dispose(); $item.Process = $null }
    if ($item.KillProcess) { $item.KillProcess.Dispose(); $item.KillProcess = $null }
    $script:activeItem = $null
    if ($item.TimedOut -or $script:engineFailure -or ($item.Status -eq 'Failed' -and $item.Definition.Required -and $script:config.Behavior.StopOnRequiredFailure)) {
        foreach ($pending in $script:items | Where-Object { $_.Status -eq 'Pending' }) { Set-ItemState $pending 'Skipped' 'Not run because an earlier step stopped setup.' }
        Finish-SetupRun
    }
    else { Start-NextStep }
}

function Start-NextStep {
    foreach ($item in $script:items) {
        if ($item.Status -ne 'Pending') { continue }
        $dependency = Get-SetupDependencyBlock -Item $item -Items $script:items
        if ($dependency) { Set-ItemState $item 'Skipped' $dependency; continue }
        $item.Attempt++
        $item.Clock = [Diagnostics.Stopwatch]::StartNew()
        $item.TimedOut = $false
        $item.LastProgress = ''
        $script:activeItem = $item
        Set-ItemState $item 'Running' 'Starting this step...'
        # Keep the current card visible when the configured list exceeds the viewport.
        $script:ui.StepList.UpdateLayout()
        $container = $script:ui.StepList.ItemContainerGenerator.ContainerFromItem($item.View)
        if ($null -ne $container) { $container.BringIntoView() }
        if (-not $script:isDemo) {
            $prefix = '{0}-attempt-{1}' -f $item.Definition.Id, $item.Attempt
            $item.LogPath = Join-Path $script:runDirectory ($prefix + '.log')
            $item.ProgressPath = Join-Path $script:runDirectory ($prefix + '.progress.json')
            $item.ResultPath = Join-Path $script:runDirectory ($prefix + '.result.json')
            $requestPath = Join-Path $script:runDirectory ($prefix + '.request.json')
            $request = [ordered]@{
                PackageRoot = $script:packageRoot; StepId = $item.Definition.Id
                RunDirectory = $script:runDirectory; ScriptPath = (Resolve-SetupContentPath $script:packageRoot $item.Definition.Script)
                Parameters = $item.Definition.Parameters; LogPath = $item.LogPath
                ProgressPath = $item.ProgressPath; ResultPath = $item.ResultPath
            }
            try {
                Write-SetupJson -Path $requestPath -Value $request
                $workerPath = Join-Path $script:packageRoot 'Core/Invoke-SetupStep.ps1'
                $powerShellPath = Join-Path $PSHOME 'powershell.exe'
                $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestPath "{1}"' -f $workerPath, $requestPath
                $launch = @{
                    FilePath = $powerShellPath; ArgumentList = $arguments; PassThru = $true
                    WindowStyle = 'Hidden'; WorkingDirectory = $script:packageRoot; ErrorAction = 'Stop'
                }
                $item.Process = Start-Process @launch
                $null = $item.Process.Handle
            }
            catch { Complete-ActiveStep -Code 1 -ErrorText ('Could not start step: ' + $_.Exception.Message) }
        }
        Update-OverallProgress
        return
    }
    Finish-SetupRun
}

function Update-ActiveStep {
    $item = $script:activeItem
    if ($null -eq $item) { return }
    if ($script:config.Appearance.ShowElapsedTime) { $item.View.Elapsed = Get-ClockText $item.Clock.Elapsed }
    if ($script:isDemo) {
        $fraction = [Math]::Min(1, $item.Clock.Elapsed.TotalSeconds / [double]$item.Definition.DemoSeconds)
        $item.View.Percent = [Math]::Floor(100 * $fraction)
        $item.View.Detail = "Preview only - simulating $($item.Definition.Title.ToLowerInvariant())"
        if ($fraction -ge 1) {
            if ($item.Definition.DemoFailFirstAttempt -and $item.Attempt -eq 1) {
                Complete-ActiveStep -Code 1 -ErrorText 'This is an intentional demo failure. Select Retry unfinished to see recovery. No step script was executed.'
            }
            else { Complete-ActiveStep -Code 0 }
        }
        return
    }
    $item.Process.Refresh()
    if ($item.TimedOut) {
        $killDone = $null -eq $item.KillProcess -or $item.KillProcess.HasExited
        if ($item.Process.HasExited -and $killDone) {
            Complete-ActiveStep -Code 1460 -ErrorText 'The step exceeded its time limit. Its process tree was asked to stop. Check installer/service activity before launching setup again. Automatic retry is disabled for this run.'
        }
        elseif ($item.Clock.Elapsed.TotalSeconds -gt ($item.Definition.TimeoutSeconds + 15)) {
            $script:engineFailure = 'The timed-out worker could not be confirmed stopped. No further steps will be started. IT must inspect the remaining processes.'
            Complete-ActiveStep -Code 1460 -ErrorText $script:engineFailure
        }
        return
    }
    if ($item.Process.HasExited) {
        $item.Process.WaitForExit()
        $code = $item.Process.ExitCode
        $errorText = ''
        if (Test-Path -LiteralPath $item.ResultPath) {
            try { $result = Get-Content -LiteralPath $item.ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json; $errorText = [string]$result.Error }
            catch { $errorText = 'Could not read step result: ' + $_.Exception.Message }
        }
        Complete-ActiveStep -Code $code -ErrorText $errorText
        return
    }
    if ($item.Clock.Elapsed.TotalSeconds -ge $item.Definition.TimeoutSeconds) {
        $item.TimedOut = $true
        $script:timeoutOccurred = $true
        $item.View.Detail = 'Time limit reached; stopping this step...'
        Write-RunLog "Timeout: stopping process tree $($item.Process.Id)."
        $killArguments = '/PID {0} /T /F' -f $item.Process.Id
        $item.KillProcess = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/taskkill.exe') -ArgumentList $killArguments -PassThru -WindowStyle Hidden
        return
    }
    if (Test-Path -LiteralPath $item.ProgressPath) {
        # A UI refresh must tolerate a brief read/share race without failing an install.
        try {
            $raw = Get-Content -LiteralPath $item.ProgressPath -Raw -Encoding UTF8
            if ($raw -ne $item.LastProgress) {
                $progress = $raw | ConvertFrom-Json
                $item.View.Detail = [string]$progress.Message
                $item.View.Percent = [Math]::Max(-1, [Math]::Min(100, [double]$progress.Percent))
                $item.LastProgress = $raw
            }
        }
        catch { }
    }
}

try {
    $taskbarId = 'PostEnrollmentSetup.' + $script:config.SetupId
    if ($script:isDemo) { $taskbarId += '.Demo' }
    [DeviceSetupUI.TaskbarIdentity]::Set($taskbarId)
    $mutexName = 'Global\PostEnrollmentSetup.' + $script:config.SetupId
    if ($script:isDemo) { $mutexName = 'Local\PostEnrollmentSetup.Demo.' + $script:config.SetupId }
    $script:mutex = New-Object Threading.Mutex($false, $mutexName)
    try { $script:hasMutex = $script:mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $script:hasMutex = $true }
    if (-not $script:hasMutex) {
        [Windows.MessageBox]::Show('A setup window for this package is already running.', 'Device Setup') | Out-Null
        exit 1618
    }

    $script:logReaderSids = @()
    $script:logAccessWarning = ''
    if ($script:isDemo) {
        $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PostEnrollmentSetupUI/Demo'
    }
    else {
        $base = [Environment]::ExpandEnvironmentVariables([string]$script:config.Behavior.StateDirectory)
        if (-not [IO.Path]::IsPathRooted($base) -or $base.StartsWith('\\')) { throw 'Behavior.StateDirectory must expand to a local absolute path.' }
        $root = Join-Path $base $script:config.SetupId
        [IO.Directory]::CreateDirectory($root) | Out-Null
        # Folder-only reader access lets Explorer navigate without granting read
        # access to Completed-*.json. Reader inheritance starts at this run folder.
        if ($identity.User.Value -eq 'S-1-5-18') {
            $script:logReaderSids = @($script:config.Behavior.LogReaderSids)
            if ($script:config.Behavior.AllowInteractiveUserToReadLogs) {
                try { $script:logReaderSids += Get-SetupLogUserSid }
                catch { $script:logAccessWarning = $_.Exception.Message }
            }
            $script:logReaderSids = @($script:logReaderSids | Sort-Object -Unique)
            Set-SetupDirectorySecurity -Path $root -ReaderSids $script:logReaderSids
        }
        try { $script:bootStamp = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o') } catch { $script:bootStamp = 'unknown' }
    }
    $runsDirectory = Join-Path $root 'Runs'
    [IO.Directory]::CreateDirectory($runsDirectory) | Out-Null
    if (-not $script:isDemo -and $identity.User.Value -eq 'S-1-5-18') {
        Set-SetupDirectorySecurity -Path $runsDirectory -ReaderSids $script:logReaderSids
    }
    $script:runDirectory = Join-Path $runsDirectory ([DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory($script:runDirectory) | Out-Null
    if (-not $script:isDemo -and $identity.User.Value -eq 'S-1-5-18') {
        Set-SetupDirectorySecurity -Path $script:runDirectory -ReaderSids $script:logReaderSids -InheritReaderAccess
    }
    $script:statePath = Join-Path $root ('Completed-' + $script:config.SetupVersion + '.json')
    $script:state = [ordered]@{ SetupId = $script:config.SetupId; SetupVersion = $script:config.SetupVersion; Completed = @{}; Declined = @{} }
    Write-RunLog "Starting. Demo=$script:isDemo; identity=$($identity.Name); config=$ConfigPath"
    if (-not $script:isDemo) {
        Write-RunLog ('Run-folder read-only SIDs: ' + ($script:logReaderSids -join ', '))
        if ($script:logAccessWarning) { Write-RunLog ('Log access: automatic reader was not added. ' + $script:logAccessWarning) }
    }
    if (-not $script:isDemo -and $ResetState -and (Test-Path -LiteralPath $script:statePath)) {
        Move-Item -LiteralPath $script:statePath -Destination ($script:statePath + '.reset-' + [Guid]::NewGuid().ToString('N'))
    }
    if (-not $script:isDemo -and $script:config.Behavior.ResumeCompletedSteps -and (Test-Path -LiteralPath $script:statePath)) {
        try {
            $saved = Get-Content -LiteralPath $script:statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.SetupId -ne $script:config.SetupId -or $saved.SetupVersion -ne $script:config.SetupVersion) { throw 'Completion record identity mismatch.' }
            foreach ($property in $saved.Completed.PSObject.Properties) { $script:state.Completed[$property.Name] = $property.Value }
            if ($null -ne $saved.PSObject.Properties['Declined']) {
                foreach ($property in $saved.Declined.PSObject.Properties) { $script:state.Declined[$property.Name] = $property.Value }
            }
        }
        catch {
            # Stop rather than silently repeat production operations with an unreadable state.
            throw ('Cannot read completion state. Inspect or archive it before retrying: ' + $script:statePath + '. ' + $_.Exception.Message)
        }
    }
    $collectionType = ('System.Collections.ObjectModel.ObservableCollection`1' -as [type]).MakeGenericType([type[]]@($script:stepViewModelType))
    $views = [Activator]::CreateInstance($collectionType)
    $fingerprints = @{}
    $index = 0
    foreach ($definition in $script:config.Steps | Where-Object Enabled) {
        $index++
        $view = [Activator]::CreateInstance($script:stepViewModelType)
        $view.Number = [string]$index
        if (-not $script:config.Appearance.ShowStepNumbers) { $view.Number = '' }
        $view.Title = $definition.Title
        $view.Description = $definition.Description
        if ($definition.UserSelectable) { $view.Description += ' (Choose to install)' }
        elseif (-not $definition.Required) { $view.Description += ' (Non-blocking)' }
        $view.IsSelected = -not $definition.UserSelectable
        $view.SelectStepLabel = $script:config.Text.SelectStepLabel
        $view.Animated = -not $script:config.Appearance.ReduceMotion
        $fingerprintInput = Get-SetupStepFingerprint $definition $script:packageRoot
        foreach ($dep in @($definition.DependsOn)) { $fingerprintInput += '|' + $fingerprints[$dep] }
        $fingerprint = Get-SetupHash $fingerprintInput
        $fingerprints[$definition.Id] = $fingerprint
        $item = [pscustomobject]@{
            Definition = $definition; View = $view; Status = 'Pending'; Fingerprint = $fingerprint
            Attempt = 0; Process = $null; KillProcess = $null; Clock = $null; TimedOut = $false
            FinalExitCode = $null; LogPath = ''; ResultPath = ''; ProgressPath = ''; LastProgress = ''
        }
        if (-not $script:isDemo -and $script:config.Behavior.ResumeCompletedSteps) {
            $resumeStatus = Get-SetupResumeStatus -Step $definition -Fingerprint $fingerprint -State $script:state -ChooseOptional:$ChooseOptional
            if ($resumeStatus -eq 'AlreadyComplete') {
                $entry = $script:state.Completed[$definition.Id]
                $item.Status = 'AlreadyComplete'; $view.Status = 'AlreadyComplete'; $view.Detail = 'Completed during an earlier run'
                if ($entry.RebootRequired -and $entry.BootStamp -eq $script:bootStamp) { $script:rebootRequired = $true }
            }
            elseif ($resumeStatus -eq 'NotSelected') {
                $item.Status = 'NotSelected'; $view.Status = 'NotSelected'; $view.Detail = 'Previously declined'
            }
        }
        $script:items += $item
        $views.Add($view)
    }
    $script:awaitingSelection = @($script:items | Where-Object { $_.Definition.UserSelectable -and $_.Status -eq 'Pending' }).Count -gt 0
    if ($script:awaitingSelection) {
        # If new choices are offered, make previously declined choices available too.
        foreach ($item in $script:items | Where-Object { $_.Definition.UserSelectable -and $_.Status -ne 'AlreadyComplete' }) {
            $item.Status = 'Pending'; $item.View.Status = 'Pending'
            $item.View.IsSelected = $false; $item.View.ShowSelection = $true
            $item.View.Detail = 'Optional - select below to include'
        }
    }
    if (-not $script:isDemo -and @($script:items | Where-Object { $_.Status -notin @('AlreadyComplete','NotSelected') }).Count -eq 0) {
        Write-RunLog 'All enabled steps complete or previously declined; no window needed.'
        $script:exitCode = 0
        if ($script:rebootRequired) { $script:exitCode = 3010 }
        Save-RunReport
        exit $script:exitCode
    }

    [xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'UI/MainWindow.xaml') -Raw -Encoding UTF8
    Set-SetupXamlTheme -Xaml $xaml -Appearance $script:config.Appearance
    $reader = New-Object Xml.XmlNodeReader($xaml)
    try { $script:window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
    foreach ($name in @('BannerContainer','BannerImage','LogoImage','CompanyLabel','DemoBadge','WelcomeHeading','WelcomeMessage','OverallHeading','ProgressCount','OverallProgress','OverallMessage','StepList','StepScroll','RebootMessage','FooterText','SupportText','ElapsedText','RetryButton','CloseButton','DiagnosticsExpander','DiagnosticText','CopyButton')) {
        $script:ui[$name] = $script:window.FindName($name)
        if ($null -eq $script:ui[$name]) { throw "Missing UI element: $name" }
    }
    $script:window.Title = $script:config.Branding.WindowTitle
    $iconPath = Resolve-SetupContentPath $script:packageRoot $script:config.Branding.IconPath
    if ($iconPath) {
        $iconStream = [IO.File]::OpenRead($iconPath)
        try {
            $icon = [Windows.Media.Imaging.BitmapFrame]::Create($iconStream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $icon.Freeze()
            $script:window.Icon = $icon
        }
        finally { $iconStream.Dispose() }
    }
    $script:window.FontFamily = New-Object Windows.Media.FontFamily($script:config.Appearance.FontFamily)
    $script:window.Topmost = $script:config.Appearance.Topmost
    $workArea = [Windows.SystemParameters]::WorkArea
    $script:window.MinWidth = [Math]::Min(640, [Math]::Max(320, $workArea.Width - 24))
    $script:window.MinHeight = [Math]::Min(520, [Math]::Max(320, $workArea.Height - 24))
    $script:window.Width = [Math]::Min($script:config.Appearance.WindowWidth, $workArea.Width - 24)
    $script:window.Height = [Math]::Min($script:config.Appearance.WindowHeight, $workArea.Height - 24)
    $script:ui.CompanyLabel.Text = $script:config.Branding.CompanyName
    $script:ui.WelcomeHeading.Text = $script:config.Branding.Heading
    $script:ui.WelcomeMessage.Text = $script:config.Branding.Message
    $script:ui.OverallHeading.Text = $script:config.Text.RunningHeading
    $script:ui.OverallMessage.Text = $script:config.Text.RunningMessage
    $script:ui.FooterText.Text = $script:config.Text.Footer
    $script:ui.SupportText.Text = $script:config.Text.Support
    $script:ui.RetryButton.Content = $script:config.Text.RetryButton
    $script:ui.CloseButton.Content = $script:config.Text.CloseButton
    $script:ui.CopyButton.Content = $script:config.Text.CopyButton
    $script:ui.DiagnosticsExpander.Header = $script:config.Text.DetailsLabel
    if (-not $script:config.Appearance.ShowElapsedTime) { $script:ui.ElapsedText.Visibility = 'Collapsed' }
    if (-not $script:isDemo) { $script:ui.DemoBadge.Visibility = 'Collapsed' }
    foreach ($kind in @('Logo','Banner')) {
        $imagePath = Resolve-SetupContentPath $script:packageRoot $script:config.Branding.($kind + 'Path')
        if ($imagePath) {
            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit(); $bitmap.CacheOption = 'OnLoad'; $bitmap.UriSource = New-Object Uri($imagePath); $bitmap.EndInit(); $bitmap.Freeze()
            $script:ui[($kind + 'Image')].Source = $bitmap
            $script:ui[($kind + 'Image')].Visibility = 'Visible'
            if ($kind -eq 'Banner') {
                $script:ui.BannerContainer.Visibility = 'Visible'
                $script:ui.BannerContainer.Height = $script:config.Branding.BannerHeight
                $script:ui.BannerImage.Stretch = $script:config.Branding.BannerStretch
                $script:ui.BannerImage.StretchDirection = $script:config.Branding.BannerStretchDirection
            }
            else { $script:ui.LogoImage.MaxWidth = $script:config.Branding.LogoMaxWidth; $script:ui.LogoImage.MaxHeight = $script:config.Branding.LogoMaxHeight }
        }
    }
    $script:ui.StepList.ItemsSource = $views
    $script:ui.DiagnosticText.Text = "$($script:config.SetupId) / $($script:config.SetupVersion)" + [Environment]::NewLine + 'Logs: ' + $script:runDirectory
    $script:ui.CloseButton.Add_Click({
        if ($script:awaitingSelection) {
            try { Start-SetupWorkflow }
            catch { $script:awaitingSelection = $false; $script:engineFailure = $_.Exception.Message; Finish-SetupRun }
        }
        elseif (-not $script:busy) { $script:window.Close() }
    })
    $script:window.Add_Closing({
        param($sender,$eventArgs)
        if ($script:busy) {
            $eventArgs.Cancel = $true
            if ($script:awaitingSelection) { $script:ui.FooterText.Text = $script:config.Text.SelectionFooter }
            else { $script:ui.FooterText.Text = 'Setup is still running. You can minimize this window.' }
        }
    })
    $script:ui.CopyButton.Add_Click({
        try {
            $lines = @($script:ui.DiagnosticText.Text)
            foreach ($item in $script:items) { $lines += "$($item.Definition.Title): $($item.Status) - $($item.View.Detail)"; if ($item.View.Error) { $lines += $item.View.Error } }
            [Windows.Clipboard]::SetText(($lines -join [Environment]::NewLine))
            $script:ui.CopyButton.Content = 'Copied'
        }
        catch { $script:ui.CopyButton.Content = 'Copy unavailable' }
    })
    $script:ui.RetryButton.Add_Click({
        if ($script:busy) { return }
        try {
            foreach ($item in $script:items | Where-Object { $_.Status -in @('Failed','Skipped') }) { Set-ItemState $item 'Pending' 'Waiting to retry'; $item.View.Percent = -1 }
            $script:busy = $true; $script:runFinishedAt = $null; $script:runClock.Start()
            $script:ui.RetryButton.Visibility = 'Collapsed'; $script:ui.CloseButton.IsEnabled = $false
            $script:ui.OverallHeading.Text = $script:config.Text.RunningHeading; $script:ui.OverallMessage.Text = $script:config.Text.RunningMessage
            $script:ui.OverallProgress.Foreground = $script:window.Resources['AccentBrush']
            Start-NextStep
        }
        catch { $script:engineFailure = $_.Exception.Message; Finish-SetupRun }
    })
    $script:timer = New-Object Windows.Threading.DispatcherTimer
    $script:timer.Interval = [TimeSpan]::FromMilliseconds($script:config.Behavior.PollIntervalMilliseconds)
    $script:timer.Add_Tick({
        try {
            if ($script:busy) { Update-ActiveStep; Update-OverallProgress }
            elseif ($script:config.Behavior.AutoCloseSuccessSeconds -gt 0 -and (Get-SetupOutcome $script:items) -eq 'Success' -and -not $script:engineFailure) {
                $remaining = [Math]::Ceiling($script:config.Behavior.AutoCloseSuccessSeconds - ([DateTime]::Now - $script:runFinishedAt).TotalSeconds)
                $script:ui.CloseButton.Content = "$($script:config.Text.CloseButton) ($remaining)"
                if ($remaining -le 0) { $script:window.Close() }
            }
        }
        catch {
            $script:engineFailure = $_.Exception.Message
            $script:timer.Stop()
            if ($null -ne $script:activeItem) {
                $active = $script:activeItem
                try { if ($active.Process -and -not $active.Process.HasExited) { $null = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/taskkill.exe') -ArgumentList ('/PID {0} /T /F' -f $active.Process.Id) -WindowStyle Hidden } } catch {}
                Set-ItemState $active 'Failed' 'The setup controller encountered an error. IT must inspect the log.' $script:engineFailure
                $script:activeItem = $null
            }
            foreach ($pending in $script:items | Where-Object { $_.Status -eq 'Pending' }) { Set-ItemState $pending 'Skipped' 'Stopped after a setup controller error.' }
            Finish-SetupRun
        }
    })
    $script:window.Add_ContentRendered({
        try {
            if ($script:hasStarted) { return }
            if ($script:awaitingSelection) {
                $script:ui.OverallHeading.Text = $script:config.Text.SelectionHeading
                $script:ui.OverallMessage.Text = $script:config.Text.SelectionMessage
                $script:ui.ProgressCount.Text = 'Choose any optional items'
                $script:ui.CloseButton.Content = $script:config.Text.StartButton
                $script:ui.CloseButton.IsEnabled = $true
                $script:ui.FooterText.Text = $script:config.Text.SelectionFooter
                # Bring the first available choice into view; no installs have started.
                $firstChoice = @($script:items | Where-Object { $_.View.ShowSelection })[0]
                $script:ui.StepList.UpdateLayout()
                $container = $script:ui.StepList.ItemContainerGenerator.ContainerFromItem($firstChoice.View)
                if ($null -ne $container) { $container.BringIntoView() }
            }
            else { Start-SetupWorkflow }
        }
        catch { $script:engineFailure = $_.Exception.Message; Finish-SetupRun }
    })
    $null = $script:window.ShowDialog()
}
catch {
    $script:exitCode = 1
    [Windows.MessageBox]::Show($_.Exception.Message, 'Device Setup encountered an error', 'OK', 'Error') | Out-Null
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
}
finally {
    if ($script:timer) { $script:timer.Stop() }
    if ($script:hasMutex) { $script:mutex.ReleaseMutex() }
    if ($script:mutex) { $script:mutex.Dispose() }
}
exit $script:exitCode
