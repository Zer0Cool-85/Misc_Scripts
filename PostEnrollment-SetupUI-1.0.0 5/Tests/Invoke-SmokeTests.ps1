#Requires -Version 5.1
<# Run on Windows with: powershell.exe -NoProfile -STA -File .\Tests\Invoke-SmokeTests.ps1
   Tests only use temporary files and a WPF window loaded in memory, not displayed.
   They do not install apps, edit HKLM, or invoke ServiceUI. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Core/Setup.Common.ps1')
$script:checks = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
    Write-Host "PASS: $Message"
}

foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1') {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Assert-True (@($errors).Count -eq 0) ("PowerShell parse: " + $file.Name)
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'Config') -Filter '*.json') {
    $cfg = Read-SetupConfiguration $file.FullName $root
    Assert-True ($cfg.SchemaVersion -eq 1) ("Configuration: " + $file.Name)
}
$stepA = [pscustomobject]@{ Definition = [pscustomobject]@{ Id='a'; Required=$true; DependsOn=@() }; Status='Complete' }
$stepB = [pscustomobject]@{ Definition = [pscustomobject]@{ Id='b'; Required=$true; DependsOn=@('a') }; Status='Failed' }
Assert-True ((Get-SetupOutcome @($stepA,$stepB)) -eq 'Failed') 'Required failure gives Failed'
$stepB.Definition.Required = $false
Assert-True ((Get-SetupOutcome @($stepA,$stepB)) -eq 'Warning') 'Optional failure gives Warning'
$stepB.Status = 'Complete'
Assert-True ((Get-SetupOutcome @($stepA,$stepB)) -eq 'Success') 'Successful steps give Success'
Assert-True ($null -eq (Get-SetupDependencyBlock $stepB @($stepA,$stepB))) 'Successful dependency allows a step'
$stepA.Status = 'Failed'
Assert-True ($null -ne (Get-SetupDependencyBlock $stepB @($stepA,$stepB))) 'Failed dependency blocks a step'
$rejected = $false
try { $null = Resolve-SetupContentPath $root '../outside.ps1' } catch { $rejected = $true }
Assert-True $rejected 'Package-relative paths cannot traverse out of the package'

function New-SelectionTestItem {
    param([string]$Id, [bool]$Choice, [bool]$Selected, [string[]]$Dependencies=@())
    [pscustomobject]@{
        Definition=[pscustomobject]@{ Id=$Id; Title=$Id; UserSelectable=$Choice; Required=(-not $Choice); DependsOn=$Dependencies }
        View=[pscustomobject]@{ IsSelected=$Selected; ShowSelection=$Choice; Status='Pending'; Detail='' }
        Status='Pending'
    }
}
$auto = New-SelectionTestItem 'automatic' $false $true
$optA = New-SelectionTestItem 'optionalA' $true $false
$optB = New-SelectionTestItem 'optionalB' $true $true @('optionalA')
$choices = @($auto,$optA,$optB)
Assert-True ($null -ne (Get-SetupSelectionBlock $choices)) 'Selected app requires its unchecked optional prerequisite'
$rejected = $false
try { Set-SetupStepSelection $choices } catch { $rejected = $true }
Assert-True ($rejected -and $optA.Status -eq 'Pending') 'Invalid selection does not partially commit'
$optA.View.IsSelected = $true
Assert-True ($null -eq (Get-SetupSelectionBlock $choices)) 'Selecting the prerequisite makes the plan valid'
Set-SetupStepSelection $choices
Assert-True (@($choices | Where-Object { $_.Status -eq 'Pending' }).Count -eq 3) 'Automatic and explicitly selected steps remain runnable'
Assert-True (@($choices | Where-Object { $_.View.ShowSelection }).Count -eq 0) 'Choices lock after the plan is committed'
$none = @( (New-SelectionTestItem 'declineA' $true $false), (New-SelectionTestItem 'declineB' $true $false) )
Set-SetupStepSelection $none
Assert-True (@($none | Where-Object { $_.Status -eq 'Pending' }).Count -eq 0) 'Unchecked apps do not enter the execution queue'
Assert-True ((Get-SetupOutcome $none) -eq 'Success') 'Choosing no optional apps is successful'
Assert-True (@($none | Where-Object { $_.Status -in @('Failed','Skipped') }).Count -eq 0) 'Retry cannot pick up declined apps'
$optA.Status = 'AlreadyComplete'; $optA.View.IsSelected = $false
Assert-True ($null -eq (Get-SetupSelectionBlock @($optA,$optB))) 'Previously completed prerequisite needs no new selection'
$resume = @{ Completed=@{}; Declined=@{optionalA=@{Fingerprint='v1'}} }
Assert-True ((Get-SetupResumeStatus $optA.Definition 'v1' $resume) -eq 'NotSelected') 'Matching declines are remembered'
Assert-True ((Get-SetupResumeStatus $optA.Definition 'v1' $resume -ChooseOptional) -eq 'Pending') 'ChooseOptional reoffers a declined app'
Assert-True ((Get-SetupResumeStatus $optA.Definition 'v2' $resume) -eq 'Pending') 'Changed execution fingerprint reoffers a declined app'
$resume.Completed.optionalA = @{Fingerprint='v1'}
Assert-True ((Get-SetupResumeStatus $optA.Definition 'v1' $resume -ChooseOptional) -eq 'AlreadyComplete') 'ChooseOptional preserves completed work'

$configTestDirectory = Join-Path ([IO.Path]::GetTempPath()) ('SetupUIConfig-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($configTestDirectory) | Out-Null
try {
    $testConfig = Get-Content -LiteralPath (Join-Path $root 'Config/Setup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($step in $testConfig.Steps) { $step.PSObject.Properties.Remove('UserSelectable') }
    $testConfig.Branding.PSObject.Properties.Remove('IconPath')
    $path = Join-Path $configTestDirectory 'Legacy.json'
    Write-SetupJson $path $testConfig
    $legacy = Read-SetupConfiguration $path $root
    Assert-True ($legacy.Behavior.AllowInteractiveUserToReadLogs -and @($legacy.Behavior.LogReaderSids).Count -eq 0) 'Old configurations default to interactive-user log read access'
    Assert-True (@($legacy.Steps | Where-Object UserSelectable).Count -eq 0 -and $legacy.Branding.IconPath -eq '') 'Old configurations retain automatic steps and get the default icon'
    $legacy.Steps[0].UserSelectable = $true
    $legacy.Steps[0].Required = $true
    Write-SetupJson $path $legacy
    $rejected = $false; try { $null = Read-SetupConfiguration $path $root } catch { $rejected = $true }
    Assert-True $rejected 'User-selectable steps cannot be required'
    $legacy.Steps[0].Required = $false
    $legacy.Steps[1].DependsOn = @($legacy.Steps[0].Id)
    Write-SetupJson $path $legacy
    $rejected = $false; try { $null = Read-SetupConfiguration $path $root } catch { $rejected = $true }
    Assert-True $rejected 'Automatic steps cannot depend on user-selectable steps'
}
finally { Remove-Item -LiteralPath $configTestDirectory -Recurse -Force }

# Exercise both the initial Move and subsequent Replace paths. Demo retry rewrites
# Results.json; live state/progress updates also overwrite previously written JSON.
$jsonTestDirectory = Join-Path ([IO.Path]::GetTempPath()) ('Setup UI JSON test ' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($jsonTestDirectory) | Out-Null
try {
    $jsonPath = Join-Path $jsonTestDirectory 'Results.json'
    Write-SetupJson -Path $jsonPath -Value ([ordered]@{ Outcome='Failed'; Attempt=1; Steps=@('a','b') })
    $saved = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($saved.Outcome -eq 'Failed' -and $saved.Attempt -eq 1) 'JSON writer creates the first result'
    foreach ($attempt in @(2,3)) {
        Write-SetupJson -Path $jsonPath -Value ([ordered]@{ Outcome='Success'; Attempt=$attempt; Steps=@('a','b') })
        $saved = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($saved.Outcome -eq 'Success' -and $saved.Attempt -eq $attempt -and @($saved.Steps).Count -eq 2) ("JSON writer replaces an existing result, attempt $attempt")
    }
    Assert-True (@(Get-ChildItem -LiteralPath $jsonTestDirectory -Force).Count -eq 1) 'JSON replacement leaves only the destination file'
}
finally { Remove-Item -LiteralPath $jsonTestDirectory -Recurse -Force }

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Re-run this test with powershell.exe -STA.' }
    Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
    # Simulate an earlier UI class cached in the same PowerShell process.
    if (-not ('DeviceSetupUI.StepViewModel' -as [type])) {
        Add-Type -TypeDefinition 'namespace DeviceSetupUI { public sealed class StepViewModel { public string Title { get; set; } } }'
    }
    $modelPath = Join-Path $root 'UI/StepViewModel.cs'
    $modelType = Import-SetupStepViewModel -Path $modelPath
    Assert-True ($modelType.FullName -ne 'DeviceSetupUI.StepViewModel' -and $null -ne $modelType.GetProperty('IsSelected')) 'Current model loads independently of a cached legacy class'
    Assert-True ((Import-SetupStepViewModel -Path $modelPath) -eq $modelType) 'Identical source reuses its compatible compiled model'
    $modelTestDirectory = Join-Path ([IO.Path]::GetTempPath()) ('SetupUIModel-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($modelTestDirectory)
    try {
        $changedPath = Join-Path $modelTestDirectory 'Changed.cs'
        $changedSource = (Get-Content -LiteralPath $modelPath -Raw -Encoding UTF8) + "`r`n// Different source revision"
        Set-Content -LiteralPath $changedPath -Value $changedSource -Encoding UTF8
        $changedType = Import-SetupStepViewModel -Path $changedPath
        Assert-True ($changedType -ne $modelType -and $null -ne $changedType.GetProperty('IsSelected')) 'Changed source gets a separate compatible type in the same process'
        $oldPath = Join-Path $modelTestDirectory 'Legacy.cs'
        Set-Content -LiteralPath $oldPath -Value 'namespace DeviceSetupUI { public sealed class StepViewModel { public string Title { get; set; } } }' -Encoding UTF8
        $rejected = $false
        try { $null = Import-SetupStepViewModel -Path $oldPath } catch { $rejected = $_.Exception.Message -like '*UI file version mismatch*IsSelected*' }
        Assert-True $rejected 'An old model file produces an actionable version-mismatch error'
    }
    finally { Remove-Item -LiteralPath $modelTestDirectory -Recurse -Force }
    $collectionType = ('System.Collections.ObjectModel.ObservableCollection`1' -as [type]).MakeGenericType([type[]]@($modelType))
    $enterpriseConfig = Read-SetupConfiguration (Join-Path $root 'Config/Enterprise-Example.json') $root
    $enterpriseItems = @(foreach ($definition in $enterpriseConfig.Steps | Where-Object Enabled) {
        $vm = [Activator]::CreateInstance($modelType)
        $vm.IsSelected = -not $definition.UserSelectable
        [pscustomobject]@{ Definition=$definition; View=$vm; Status='Pending' }
    })
    Set-SetupStepSelection -Items $enterpriseItems
    Assert-True ($enterpriseItems.Count -eq 5 -and @($enterpriseItems | Where-Object { -not $_.View.IsSelected -or $_.View.ShowSelection -or $_.Status -ne 'Pending' }).Count -eq 0) 'Enterprise example initializes all five automatic steps without optional selection'
    if (-not ('DeviceSetupUI.TaskbarIdentity' -as [type])) { Add-Type -Path (Join-Path $root 'UI/TaskbarIdentity.cs') }
    Assert-True ($null -ne ('DeviceSetupUI.TaskbarIdentity' -as [type])) 'Taskbar helper compiles without changing the test host identity'
    $themeCases = @(foreach ($configName in @('Setup.json','Dark-Demo.json','All10-Demo.json','Enterprise-Example.json')) {
        [pscustomobject]@{ Label=$configName; Config=(Read-SetupConfiguration (Join-Path $root ('Config/' + $configName)) $root) }
    })
    $custom = Read-SetupConfiguration (Join-Path $root 'Config/Setup.json') $root
    $custom.Appearance.AccentColor = '#7C3AED'
    $custom.Appearance.SuccessColor = '#008A61'
    $custom.Appearance.FailureColor = '#BE123C'
    $custom.Appearance.WarningColor = '#B45309'
    $themeCases += [pscustomobject]@{ Label='Custom colors'; Config=$custom }
    foreach ($themeCase in $themeCases) {
        [xml]$xml = Get-Content -LiteralPath (Join-Path $root 'UI/MainWindow.xaml') -Raw -Encoding UTF8
        Set-SetupXamlTheme -Xaml $xml -Appearance $themeCase.Config.Appearance
        $reader = New-Object Xml.XmlNodeReader($xml)
        try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
        try {
            Assert-True ($null -ne $window.FindName('StepList')) ("Themed WPF XAML loads: " + $themeCase.Label)
            Assert-True ($window.Icon -is [Windows.Media.ImageSource]) 'Built-in setup window icon resolves'
            $items = [Activator]::CreateInstance($collectionType)
            1..10 | ForEach-Object {
                $vm = [Activator]::CreateInstance($modelType)
                $vm.Number = [string]$_; $vm.Title = "Test step $_"; $vm.Description = 'Layout check'; $vm.Animated = $true
                $items.Add($vm)
            }
            $window.FindName('StepList').ItemsSource = $items
            $items[0].Status = 'Running'; $items[0].Percent = 50
            $items[1].Status = 'Failed'; $items[1].Error = 'Test error'
            $items[2].Status = 'Complete'; $items[3].Status = 'Skipped'
            $items[4].ShowSelection = $true; $items[4].IsSelected = $false; $items[4].SelectStepLabel = 'Include this optional step'
            $items[5].Status = 'NotSelected'
            $window.Measure((New-Object Windows.Size(900,820)))
            $window.Arrange((New-Object Windows.Rect(0,0,900,820)))
            $window.UpdateLayout()
            Assert-True ($items[1].HasError -and $items[0].HasPercent) 'Step model exposes error/progress state'
            Assert-True ($window.Background -is [Windows.Media.SolidColorBrush]) ("Window Background resolves to a brush: " + $themeCase.Label)
            foreach ($role in @('Accent','Success','Failure','Warning')) {
                $brush = $window.Resources[$role + 'Brush']
                $expected = '#FF' + $themeCase.Config.Appearance.($role + 'Color').Substring(1)
                Assert-True ($brush -is [Windows.Media.SolidColorBrush] -and $brush.Color.ToString() -eq $expected) ("Configured $role brush: " + $themeCase.Label)
            }
            $expectedAccent = '#FF' + $themeCase.Config.Appearance.AccentColor.Substring(1)
            Assert-True ($window.FindName('CloseButton').Background.Color.ToString() -eq $expectedAccent) ("Button Background resolves the accent: " + $themeCase.Label)
            if ($themeCase.Config.Appearance.Theme -eq 'Dark') {
                Assert-True ($window.Background.Color.ToString() -eq '#FF151C29') 'Dark canvas color is applied'
            }
        }
        finally { $window.Close() }
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ('SetupUISmoke-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        foreach ($test in @(
            @{Name='success'; Code=0; Body='Write-SetupProgress -Message "Test progress" -Percent 50; Write-SetupProgress -Message "Finished" -Percent 100; Write-Output "Done"'},
            @{Name='failure'; Code=1; Body='throw "Intentional smoke-test failure"'},
            @{Name='nativeexit'; Code=3010; Body='exit 3010'},
            @{Name='helperreboot'; Code=3010; Body='$null = Invoke-SetupProcess -FilePath $env:ComSpec -Arguments "/c exit 3010"'}
        )) {
            $file = Join-Path $temp ($test.Name + '.ps1')
            [IO.File]::WriteAllText($file, $test.Body)
            $request = [ordered]@{
                PackageRoot=$root; StepId=$test.Name; RunDirectory=$temp; ScriptPath=$file; Parameters=@{}
                LogPath=(Join-Path $temp ($test.Name+'.log')); ProgressPath=(Join-Path $temp ($test.Name+'.progress.json'))
                ResultPath=(Join-Path $temp ($test.Name+'.result.json'))
            }
            $requestFile = Join-Path $temp ($test.Name+'.request.json')
            Write-SetupJson $requestFile $request
            $argsText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestPath "{1}"' -f (Join-Path $root 'Core/Invoke-SetupStep.ps1'),$requestFile
            $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argsText -Wait -PassThru
            Assert-True ($process.ExitCode -eq $test.Code) ("Worker exit code: " + $test.Name)
            if ($test.Name -eq 'success') {
                $progress = Get-Content -LiteralPath $request.ProgressPath -Raw | ConvertFrom-Json
                Assert-True ($progress.Percent -eq 100 -and $progress.Message -eq 'Finished') 'Worker replaces earlier progress with the latest update'
            }
            if ($test.Name -eq 'failure') {
                $result = Get-Content -LiteralPath $request.ResultPath -Raw | ConvertFrom-Json
                Assert-True ($result.Error -like '*Intentional smoke-test failure*') 'Worker captures failure details'
            }
        }
    }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "All $script:checks checks passed. ServiceUI/session/DPI checks are still manual; see Docs/TESTING.md."
