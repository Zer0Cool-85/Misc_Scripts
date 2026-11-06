[CmdletBinding()]
param([string]$NameTemplate='{Prefix}-{Serial:7}', [string]$Prefix='PC', [string]$Site='',
      [string]$LaptopCode='L', [string]$DesktopCode='D', [bool]$PreviewOnly=$false)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
. (Join-Path $PSScriptRoot 'Provisioning.Common.ps1')
$machine=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
$serial=''; $asset=''; $uuid=''; $mobile=$machine.PCSystemType -eq 2
if ($NameTemplate -match '\{Serial[:}]') { $serial=(Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber }
if ($NameTemplate -match '\{(Asset|Type)[:}]') {
    $case=Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop | Select-Object -First 1
    if ($case) { $asset=$case.SMBIOSAssetTag; $mobile=$mobile -or @($case.ChassisTypes | Where-Object { $_ -in @(8,9,10,11,14,30,31,32) }).Count -gt 0 }
}
if ($NameTemplate -match '\{Hash[:}]') { $uuid=(Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop | Select-Object -First 1).UUID }
$type=if ($mobile) { $LaptopCode } else { $DesktopCode }
$name=Get-DeviceNameValue -Template $NameTemplate -Prefix $Prefix -Site $Site -Type $type -Serial $serial -AssetTag $asset -Uuid $uuid
$active=[Environment]::MachineName
$pending=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName).ComputerName
Set-EnterpriseProgress "Computer name: active=$active; configured=$pending; proposed=$name."
if ($PreviewOnly) { $global:SetupUiStepSummary="Preview: $active -> $name (no change)."; return }
if ($pending -ne $active -and $pending -ne $name) { throw "A different rename to '$pending' is already pending. Reconcile the other naming policy." }
if ($pending -eq $name) {
    $global:SetupUiStepSummary="Configured computer name: $name"
    if ($active -ne $name) { $global:SetupUiRebootRequired=$true }
    return
}
if ($machine.PartOfDomain) { throw 'This step is for Entra-only or workgroup PCs. An AD-domain rename needs a separately authorized workflow.' }
Rename-Computer -NewName $name -Force -ErrorAction Stop
$pending=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName).ComputerName
if ($pending -ne $name) { throw "Windows did not stage the requested name '$name'." }
$global:SetupUiRebootRequired=$true
$global:SetupUiStepSummary="Staged computer name: $name"
Set-EnterpriseProgress "Rename to $name verified; takes effect at restart."
