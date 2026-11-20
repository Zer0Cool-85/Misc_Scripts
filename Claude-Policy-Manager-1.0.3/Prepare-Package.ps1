#requires -Version 5.1
[CmdletBinding()]
param([string]$IntuneWinAppUtilPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Source\PolicyEngine.psm1') -Force -DisableNameChecking
$source=Join-Path $PSScriptRoot 'Source'
$config=Read-PolicyConfiguration (Join-Path $source 'PolicyConfig.json')
$files=[ordered]@{}
foreach ($name in @('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1')) {$files[$name]=Get-FileDigest (Join-Path $source $name)}
$manifest=[ordered]@{SchemaVersion=1;PackageVersion=(Get-ManagerVersion);ConfigurationId=$config.ConfigurationId;Files=$files}
$manifestPath=Join-Path $source 'PackageManifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
$template=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Tools\Detect-Template.ps1') -Raw
$detection=$template.Replace('__MANIFEST_SHA256__',(Get-FileDigest $manifestPath))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'Detect-Installation.ps1'),$detection,(New-Object Text.UTF8Encoding($true)))
Write-Output "Prepared $($config.ConfigurationId); direct instructions=$($config.Desired.Count). Detection: Detect-Installation.ps1"
if ($IntuneWinAppUtilPath) {
    if (-not (Test-Path -LiteralPath $IntuneWinAppUtilPath -PathType Leaf)) {throw 'IntuneWinAppUtil.exe not found.'}
    $output=Join-Path $PSScriptRoot 'Output'
    if (-not (Test-Path -LiteralPath $output)) {[void](New-Item -ItemType Directory -Path $output)}
    & $IntuneWinAppUtilPath -c $source -s Install.cmd -o $output -q
    if ($LASTEXITCODE -ne 0) {throw "IntuneWinAppUtil failed: $LASTEXITCODE"}
    Write-Output "Win32 package created in $output"
}
