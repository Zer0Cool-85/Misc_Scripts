[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
# The controller owns restart timing after it persists results; never reboot inside a worker.
Set-EnterpriseProgress 'Final setup requires a restart. Save any open work.'
$global:SetupUiRebootRequired=$true
