[CmdletBinding()]
param([string]$RegistryPath = 'HKLM:\SOFTWARE\Company\PostEnrollmentSetup', [string]$TargetUserSid = '')
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
try {
    $sid = Get-EnterpriseUserSid $TargetUserSid
    $present = Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid
    Set-CompanyPortalState -RegistryPath $RegistryPath -UserSid $sid -Present $present
    $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq 'Microsoft.CompanyPortal').Count -gt 0
    Set-EnterpriseProgress "Company Portal registered/healthy: $present; provisioned: $provisioned. NeedsCompanyPortal=$([int](-not $present))."
    # Missing is a recorded finding, not a failure; the dependent installer must run.
}
catch { Write-EnterpriseLog -Level ERROR -Message $_.Exception.Message; throw }
