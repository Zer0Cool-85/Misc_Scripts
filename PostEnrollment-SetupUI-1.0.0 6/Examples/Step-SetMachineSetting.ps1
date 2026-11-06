# Example only. Not referenced by the default configuration.
# This deliberately uses an example key; replace it with your actual setting.
[CmdletBinding()]
param([string]$RegistryPath = 'HKLM:\SOFTWARE\YourCompany\DeviceSetupExample')
$ErrorActionPreference = 'Stop'
Write-SetupProgress -Message 'Applying the machine setting...' -Percent 25
$null = New-Item -Path $RegistryPath -Force
$null = New-ItemProperty -Path $RegistryPath -Name 'Configured' -Value 1 -PropertyType DWord -Force
if ((Get-ItemPropertyValue -Path $RegistryPath -Name 'Configured') -ne 1) { throw 'Registry verification failed.' }
Write-SetupProgress -Message 'Machine setting verified.' -Percent 100
