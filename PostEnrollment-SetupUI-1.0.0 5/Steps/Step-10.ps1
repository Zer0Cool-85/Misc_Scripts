# Step 10: Additional step 10
# This script runs as SYSTEM when launched with your SYSTEM + ServiceUI workflow.
# Each step has a fresh 64-bit Windows PowerShell 5.1 process.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# Replace the throw below with your real implementation.
# Leave it in place until this step is ready; placeholders must never report success.
throw 'Step 10 is not configured. Edit Steps/Step-10.ps1 before using -Live.'

# Helpers supplied by Core/Invoke-SetupStep.ps1:
# Write-SetupProgress -Message 'Installing application...' -Percent 30
# $installer = Join-Path $env:SETUP_PACKAGE_ROOT 'Files/AppSetup.exe'
# $null = Invoke-SetupProcess -FilePath $installer -Arguments '/quiet /norestart'
# Write-SetupProgress -Message 'Validating the result...' -Percent 90
# if (-not (Test-Path -LiteralPath 'C:/Program Files/Vendor/App/App.exe')) {
#     throw 'Application verification failed.'
# }
# Write-SetupProgress -Message 'Installation verified.' -Percent 100
# Return normally for success; throw for failure. See Docs/STEP-AUTHORING.md.
