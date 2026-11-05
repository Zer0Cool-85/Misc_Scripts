# Example only. Not referenced by the default configuration.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsiRelativePath,
    [Parameter(Mandatory)][string]$ExpectedFile
)
$ErrorActionPreference = 'Stop'
$msi = Join-Path $env:SETUP_PACKAGE_ROOT $MsiRelativePath
if (-not (Test-Path -LiteralPath $msi -PathType Leaf)) { throw "Missing MSI: $msi" }
if (Test-Path -LiteralPath $ExpectedFile -PathType Leaf) {
    Write-SetupProgress -Message 'Already installed; verification passed.' -Percent 100
    return
}
Write-SetupProgress -Message 'Installing the application...' -Percent 15
$installerLog = Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID + '-msi.log')
$arguments = '/i "{0}" /qn /norestart /L*v "{1}"' -f $msi, $installerLog
$null = Invoke-SetupProcess -FilePath (Join-Path $env:SystemRoot 'System32/msiexec.exe') -Arguments $arguments
Write-SetupProgress -Message 'Checking the installed files...' -Percent 95
if (-not (Test-Path -LiteralPath $ExpectedFile -PathType Leaf)) { throw "Install returned success, but expected file was not found: $ExpectedFile" }
Write-SetupProgress -Message 'Installation verified.' -Percent 100
# Invoke-SetupProcess preserves a 3010 reboot-required result for the worker.
# In production, use your real version/product detection instead of just file presence.
