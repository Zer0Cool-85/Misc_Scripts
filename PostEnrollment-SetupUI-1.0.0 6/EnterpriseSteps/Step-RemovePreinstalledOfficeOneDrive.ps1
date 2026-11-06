[CmdletBinding()]
param(
    [string[]]$OfficeProductIds = @('O365HomePremRetail'),
    [string]$OdtRelativePath = 'Payloads/ODT/setup.exe',
    [bool]$AllowBusinessOfficeRemoval = $false,
    [bool]$RemoveOfficeHub = $true,
    [bool]$RemoveStoreOfficeDesktop = $false,
    [bool]$RemoveOneDrive = $true,
    [bool]$ForceCloseApps = $false,
    [string]$TargetUserSid = '',
    [ValidateSet('SelectedProducts','AllOffice')][string]$OfficeRemovalMode='SelectedProducts',
    [string]$GetHelpRelativePath='Payloads/GetHelp/GetHelpCmd.exe',
    [bool]$AuditOnly=$false
)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
. (Join-Path $PSScriptRoot 'Provisioning.Common.ps1')
function Get-OfficeProducts {
    $key = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path -LiteralPath $key) {
        $p = Get-ItemProperty -LiteralPath $key
        if ($null -ne $p.PSObject.Properties['ProductReleaseIds']) { return @(([string]$p.ProductReleaseIds -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    }
}
function Get-MachineOneDrive {
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (Test-Path $root) {
            Get-ChildItem -LiteralPath $root | ForEach-Object {
                $p = Get-ItemProperty -LiteralPath $_.PSPath
                if ($null -ne $p.PSObject.Properties['DisplayName'] -and $p.DisplayName -eq 'Microsoft OneDrive') { $p }
            }
        }
    }
}
function Wait-Removal {
    param([scriptblock]$StillPresent, [string]$Label)
    for ($i = 0; $i -lt 30; $i++) {
        if (-not (& $StillPresent)) { return }
        Start-Sleep -Seconds 2
    }
    throw "$Label remains detected after uninstall. Review logs and pending restart before retrying."
}
try {
    $all = $OfficeRemovalMode -eq 'AllOffice'
    $receipt='HKLM:\SOFTWARE\PostEnrollmentSetupUI\OfficeBaseline'
    $baselineDone=$false
    if ($all -and (Test-Path -LiteralPath $receipt)) { $baselineDone=([string](Get-Item -LiteralPath $receipt).GetValue('AllDesktopOfficeRemoved') -eq '1') }
    $desktop=@()
    if ($all -and (-not $baselineDone -or $AuditOnly)) { $desktop=@(Get-OfficeDesktopEvidence | Sort-Object -Unique) }
    if ($AuditOnly) {
        $apps=@('Microsoft.MicrosoftOfficeHub','Microsoft.Office.Desktop','Microsoft.Office.OneNote','Microsoft.OutlookForWindows','Microsoft.Office.Word','Microsoft.Office.Excel','Microsoft.Office.PowerPoint')
        $registered=@(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -in $apps } | Select-Object -ExpandProperty Name -Unique)
        $provisioned=@(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -in $apps } | Select-Object -ExpandProperty DisplayName -Unique)
        if (-not $all) { $desktop=@(Get-OfficeProducts | Where-Object { $_ -in $OfficeProductIds }) }
        Write-EnterpriseLog ('Office inventory: '+($desktop -join '; ')+'; Store registered: '+($registered -join ', ')+'; provisioned: '+($provisioned -join ', ')+"; broad cleanup previously completed: $baselineDone")
        Set-EnterpriseProgress 'Office inventory saved to SetupUI.log; audit mode made no changes.'
        return
    }
    foreach ($id in $OfficeProductIds) {
        if ($id -notmatch '^O365[A-Za-z0-9]+Retail$') { throw "Only explicit O365 product IDs are permitted: $id" }
        if ($id -ne 'O365HomePremRetail' -and -not $AllowBusinessOfficeRemoval) { throw 'Set AllowBusinessOfficeRemoval=true to remove any Office suite other than O365HomePremRetail.' }
    }
    if (-not $all -and $RemoveStoreOfficeDesktop -and -not $AllowBusinessOfficeRemoval) { throw 'Store Office Desktop removal also requires AllowBusinessOfficeRemoval=true.' }
    $targets = @(Get-OfficeProducts | Where-Object { $_ -in $OfficeProductIds })
    $appNames = @()
    if ($RemoveOfficeHub) { $appNames += 'Microsoft.MicrosoftOfficeHub' }
    if ($RemoveStoreOfficeDesktop) { $appNames += 'Microsoft.Office.Desktop' }
    if ($all) {
        $targets=@()
        $appNames=if ($baselineDone) { @() } else { @('Microsoft.Office.Desktop','Microsoft.MicrosoftOfficeHub','Microsoft.Office.OneNote','Microsoft.OutlookForWindows','Microsoft.Office.Word','Microsoft.Office.Excel','Microsoft.Office.PowerPoint') }
        if ($baselineDone) { Write-EnterpriseLog 'Office baseline already applied. Leaving subsequently licensed Office installations intact.' }
    }
    # Inspect before changing anything. This step is intended for freshly enrolled PCs.
    $processNames = @()
    if ($targets.Count -or $desktop.Count -or ($RemoveStoreOfficeDesktop -and -not $baselineDone)) { $processNames += @('WINWORD','EXCEL','POWERPNT','OUTLOOK','ONENOTE','MSACCESS','MSPUB','WINPROJ','VISIO') }
    if ($RemoveOneDrive) { $processNames += 'OneDrive' }
    $running = @()
    if ($processNames.Count) { $running = @(Get-Process -Name $processNames -ErrorAction SilentlyContinue) }
    if ($running.Count -and -not $ForceCloseApps) { throw 'Office/OneDrive is running. Close the apps and finish syncing, then retry. ForceCloseApps is false.' }
    $getHelp=$null; $broadOdt=$null
    if ($all -and $desktop.Count -and @(Get-OfficeProducts).Count -gt 0 -and $OdtRelativePath) {
        $candidate=Resolve-SetupContentPath $env:SETUP_PACKAGE_ROOT $OdtRelativePath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { Assert-MicrosoftBinary $candidate; $broadOdt=$candidate }
    }
    $odt = $null
    if ($targets.Count) { $odt = Resolve-EnterpriseFile $OdtRelativePath; Assert-MicrosoftBinary $odt }
    if ($running.Count) { Write-EnterpriseLog -Level WARN -Message 'ForceCloseApps enabled; stopping Office/OneDrive processes.'; $running | Stop-Process -Force -ErrorAction Stop }
    if ($broadOdt) {
        Set-EnterpriseProgress 'Removing all Click-to-Run Office products, languages, Project and Visio.'
        $xml=[xml]'<Configuration><Remove All="TRUE"/><Display Level="None" AcceptEULA="TRUE"/><Property Name="FORCEAPPSHUTDOWN" Value="FALSE"/></Configuration>'
        if ($ForceCloseApps) { $xml.Configuration.Property.SetAttribute('Value','TRUE') }
        $xmlPath=Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID+'-AllOffice.xml')
        $xml.Save($xmlPath); Invoke-SetupProcess $broadOdt ('/configure "{0}"' -f $xmlPath) | Out-Null
        Wait-Removal -Label 'Click-to-Run Office products' -StillPresent { @(Get-OfficeProducts).Count -gt 0 }
        $desktop=@(Get-OfficeDesktopEvidence | Sort-Object -Unique)
    }
    if ($all -and $desktop.Count) { $getHelp=Resolve-EnterpriseFile $GetHelpRelativePath; Assert-MicrosoftBinary $getHelp }
    if ($getHelp) {
        Write-EnterpriseLog ('Office evidence before removal: '+($desktop -join '; '))
        Set-EnterpriseProgress 'Removing all detected Office versions with Microsoft Get Help.'
        $log=Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID+'-GetHelp')
        $native=Start-Process -FilePath $getHelp -ArgumentList '-S OfficeScrubScenario -AcceptEula -OfficeVersion All' -WorkingDirectory (Split-Path $getHelp -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput ($log+'.out.log') -RedirectStandardError ($log+'.err.log') -ErrorAction Stop
        if ($native.ExitCode -notin @(0,3010)) { throw "Get Help exit $($native.ExitCode); see $log.out.log" }
        Wait-Removal -Label 'Desktop Office (including Visio/Project)' -StillPresent { @(Get-OfficeDesktopEvidence).Count -gt 0 }
        $global:SetupUiRebootRequired=$true
    }
    if ($targets.Count) {
        Set-EnterpriseProgress ('Removing Office products: ' + ($targets -join ', '))
        $xml = [xml]'<Configuration><Remove All="FALSE"/><Display Level="None" AcceptEULA="TRUE"/><Property Name="FORCEAPPSHUTDOWN" Value="FALSE"/></Configuration>'
        foreach ($id in $targets) { $product = $xml.CreateElement('Product'); $product.SetAttribute('ID', $id); [void]$xml.Configuration.Remove.AppendChild($product) }
        if ($ForceCloseApps) { $xml.Configuration.Property.SetAttribute('Value', 'TRUE') }
        $xmlPath = Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID + '-OfficeRemove.xml')
        $xml.Save($xmlPath)
        Invoke-SetupProcess -FilePath $odt -Arguments ('/configure "{0}"' -f $xmlPath) | Out-Null
        Wait-Removal -Label 'Selected Click-to-Run Office products' -StillPresent { @(Get-OfficeProducts | Where-Object { $_ -in $targets }).Count -gt 0 }
        Write-EnterpriseLog 'Office product removal verified. ODT logs are normally in the executing account TEMP directory (SYSTEM: Windows\Temp).'
    }
    elseif (-not $all) { Write-EnterpriseLog 'No allowlisted Click-to-Run Office products found.' }
    foreach ($name in $appNames) {
        Set-EnterpriseProgress "Checking Store app $name."
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $name | ForEach-Object {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
        }
        # AllUsers removal uses the parent package. Remove bundles first, then
        # re-query any standalone main packages so no removed child is reused.
        Get-AppxPackage -AllUsers -Name $name -PackageTypeFilter Bundle -ErrorAction Stop | Sort-Object PackageFullName -Unique | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
        }
        Get-AppxPackage -AllUsers -Name $name -PackageTypeFilter Main -ErrorAction Stop | Sort-Object PackageFullName -Unique | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
        }
        if (@(Get-AppxPackage -AllUsers -Name $name).Count -or @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $name).Count) { throw "Store app $name remains installed/provisioned." }
    }
    if ($all -and -not $baselineDone) {
        if (@(Get-OfficeDesktopEvidence).Count) { throw 'Desktop Office remains detected. Do not mark this baseline complete.' }
        New-Item -Path $receipt -Force | Out-Null
        New-ItemProperty -LiteralPath $receipt -Name AllDesktopOfficeRemoved -PropertyType DWord -Value 1 -Force | Out-Null
        Write-EnterpriseLog 'Broad Office cleanup verified; first-provisioning receipt saved.'
    }
    if ($RemoveOneDrive) {
        $sid = Get-EnterpriseUserSid $TargetUserSid
        foreach ($entry in @(Get-MachineOneDrive)) {
            if (-not (Test-Path -LiteralPath $entry.PSPath)) { continue }
            $command = [string]$entry.UninstallString
            if ($command -notmatch '^"(?<exe>[^"\r\n]+OneDriveSetup\.exe)"\s+/uninstall(?:\s+.*)?$') { throw 'Unrecognized machine OneDrive uninstaller command.' }
            $exe = [IO.Path]::GetFullPath($Matches.exe)
            $trusted = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:SystemRoot) | Where-Object { $_ -and $exe.StartsWith(($_.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase) }
            if (-not $trusted) { throw 'Refusing to run a machine uninstaller outside Program Files or Windows.' }
            Assert-MicrosoftBinary $exe
            Set-EnterpriseProgress 'Removing machine-wide OneDrive.'
            Invoke-SetupProcess -FilePath $exe -Arguments '/uninstall /allusers' | Out-Null
        }
        Wait-Removal -Label 'Machine OneDrive' -StillPresent { @(Get-MachineOneDrive).Count -gt 0 }
        $userKey = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
        if (Test-Path -LiteralPath $userKey) {
            Set-EnterpriseProgress 'Removing OneDrive for the signed-in user.'
            Invoke-EnterpriseUserAction -UserSid $sid -Request @{Action='UninstallOneDrive'}
            Wait-Removal -Label 'User OneDrive' -StillPresent { Test-Path -LiteralPath $userKey }
        }
        # Never load other profiles or execute their uninstallers as SYSTEM.
        Write-EnterpriseLog 'OneDrive machine/current-user removal verified. Other existing user profiles are outside this first-logon step scope. User data folders were not deleted.'
    }
    Set-EnterpriseProgress 'Selected preinstalled app cleanup completed.'
}
catch { Write-EnterpriseLog -Level ERROR -Message $_.Exception.Message; throw }
