[CmdletBinding()]
param(
    [string[]]$OfficeProductIds = @('O365HomePremRetail'),
    [string]$OdtRelativePath = 'Payloads/ODT/setup.exe',
    [bool]$AllowBusinessOfficeRemoval = $false,
    [bool]$RemoveOfficeHub = $true,
    [bool]$RemoveStoreOfficeDesktop = $false,
    [bool]$RemoveOneDrive = $true,
    [bool]$ForceCloseApps = $false,
    [string]$TargetUserSid = ''
)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
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
    foreach ($id in $OfficeProductIds) {
        if ($id -notmatch '^O365[A-Za-z0-9]+Retail$') { throw "Only explicit O365 product IDs are permitted: $id" }
        if ($id -ne 'O365HomePremRetail' -and -not $AllowBusinessOfficeRemoval) { throw 'Set AllowBusinessOfficeRemoval=true to remove any Office suite other than O365HomePremRetail.' }
    }
    if ($RemoveStoreOfficeDesktop -and -not $AllowBusinessOfficeRemoval) { throw 'Store Office Desktop removal also requires AllowBusinessOfficeRemoval=true.' }
    $targets = @(Get-OfficeProducts | Where-Object { $_ -in $OfficeProductIds })
    $appNames = @()
    if ($RemoveOfficeHub) { $appNames += 'Microsoft.MicrosoftOfficeHub' }
    if ($RemoveStoreOfficeDesktop) { $appNames += 'Microsoft.Office.Desktop' }
    # Inspect before changing anything. This step is intended for freshly enrolled PCs.
    $processNames = @()
    if ($targets.Count -or $RemoveStoreOfficeDesktop) { $processNames += @('WINWORD','EXCEL','POWERPNT','OUTLOOK','ONENOTE','MSACCESS','MSPUB') }
    if ($RemoveOneDrive) { $processNames += 'OneDrive' }
    $running = @()
    if ($processNames.Count) { $running = @(Get-Process -Name $processNames -ErrorAction SilentlyContinue) }
    if ($running.Count -and -not $ForceCloseApps) { throw 'Office/OneDrive is running. Close the apps and finish syncing, then retry. ForceCloseApps is false.' }
    $odt = $null
    if ($targets.Count) { $odt = Resolve-EnterpriseFile $OdtRelativePath; Assert-MicrosoftBinary $odt }
    if ($running.Count) { Write-EnterpriseLog -Level WARN -Message 'ForceCloseApps enabled; stopping Office/OneDrive processes.'; $running | Stop-Process -Force -ErrorAction Stop }
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
    else { Write-EnterpriseLog 'No allowlisted Click-to-Run Office products found.' }
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
