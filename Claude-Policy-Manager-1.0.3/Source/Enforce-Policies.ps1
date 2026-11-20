#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$lock=$null
try {
    # Verify the module before importing executable code from the protected directory.
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PackageManifest.json') -Raw | ConvertFrom-Json
    $modulePath=Join-Path $PSScriptRoot 'PolicyEngine.psm1'
    $actual=(Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $manifest.Files.'PolicyEngine.psm1') {throw 'Engine integrity failed; redeploy the assigned Win32 package.'}
    Import-Module $modulePath -Force -DisableNameChecking
    Assert-Administrator
    if ($PSScriptRoot -ine (Get-ManagerRoot)) {throw 'Enforcement must run from the installed manager directory.'}
    $lock=Enter-ManagerLock $PSScriptRoot
    foreach ($item in @(Get-SafeTree $PSScriptRoot)) {
        if ($item.Name -ne 'Operation.lock') {Assert-PrivatePermissions $item.FullName}
    }
    $null=Read-PackageManifest $PSScriptRoot
    $config=Read-PolicyConfiguration (Join-Path $PSScriptRoot 'PolicyConfig.json')
    $null=Invoke-PolicyEnforcement $PSScriptRoot $config
    Ensure-RegistryAuditing $PSScriptRoot $config
    exit 0
} catch {
    $message=$_.Exception.Message
    # Only use the imported logger after payload verification succeeded.
    if (Get-Command Write-ManagerLog -ErrorAction SilentlyContinue) {
        try {Write-ManagerLog $PSScriptRoot "Enforcement failed: $message"} catch {}
    }
    Write-Error $message -ErrorAction Continue
    exit 1
} finally {if ($null -ne $lock) {$lock.Dispose()}}
