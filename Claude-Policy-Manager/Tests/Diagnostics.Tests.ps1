#requires -Version 5.1
# Isolated child-process tests; no real Windows registry/task/ACL/audit changes.
$ErrorActionPreference='Stop'
$bundle=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeDiagnostics-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $temp)
$script:Count=0
function Assert($ok,$text) {if (-not $ok) {throw "FAIL: $text"};$script:Count++;Write-Output "PASS: $text"}
$exe=Join-Path $PSHOME 'pwsh';if (-not (Test-Path $exe)) {$exe=Join-Path $PSHOME 'powershell.exe'}
$oldProgramData=$env:ProgramData;$oldSystemRoot=$env:SystemRoot
try {
    $pkg=Join-Path $temp 'Source';[void](New-Item -ItemType Directory $pkg)
    $installer=Join-Path $pkg 'Install-PolicyManager.ps1'
    Copy-Item (Join-Path $bundle 'Source/Install-PolicyManager.ps1') $installer
    $output=& $exe -NoProfile -File $installer 2>&1
    Assert ($LASTEXITCODE -eq 1) 'Missing engine reports failure'
    Assert (($output | Out-String) -match 'INSTALL FAILED during stage: Loading policy engine') 'Missing engine is captured before module import'
    Assert (($output | Out-String) -match 'Install-PolicyManager.ps1:') 'Early exception includes source position'
    Copy-Item (Join-Path $bundle 'Source/*') $pkg -Force
    $module=Join-Path $pkg 'PolicyEngine.psm1'
    [IO.File]::AppendAllText($module,"`nfunction Assert-Administrator {}`nfunction Initialize-PrivateRoot {throw 'Injected pre-logger folder failure'}`nExport-ModuleMember -Function *`n")
    $output=& $exe -NoProfile -File $installer 2>&1
    Assert ($LASTEXITCODE -eq 1 -and ($output | Out-String) -match 'Validating package manifest and payload hashes') 'Missing manifest identifies the stage'
    Copy-Item (Join-Path $bundle 'Examples/Config-1-ChatOnly.json') (Join-Path $pkg 'PolicyConfig.json') -Force
    $files=[ordered]@{}
    foreach ($n in @('PolicyConfig.json','PolicyEngine.psm1','Enforce-Policies.ps1')) {$files[$n]=(Get-FileHash (Join-Path $pkg $n)).Hash.ToLowerInvariant()}
    $config=Get-Content (Join-Path $pkg 'PolicyConfig.json') -Raw | ConvertFrom-Json
    @{SchemaVersion=1;PackageVersion='1.0.1';ConfigurationId=$config.ConfigurationId;Files=$files} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $pkg 'PackageManifest.json')
    $output=& $exe -NoProfile -File $installer 2>&1
    Assert ($LASTEXITCODE -eq 1 -and ($output | Out-String) -match 'Injected pre-logger folder failure') 'Pre-logger folder failure remains visible'
    Assert (($output | Out-String) -match 'INSTALL FAILED during stage: Creating or validating secured manager folder') 'Folder failure identifies its stage'
    Assert (($output | Out-String) -match 'Script stack:.*Initialize-PrivateRoot') 'Folder failure preserves the script stack'
    $env:ProgramData=Join-Path $temp 'ProgramData';$env:SystemRoot=Join-Path $temp 'Windows'
    $logs=Join-Path $env:ProgramData 'Microsoft/IntuneManagementExtension/Logs';[void](New-Item -ItemType Directory $logs -Force)
    $env:CPM_DIAGNOSTIC_ROOT=Join-Path $temp 'NotInstalled'
    $template=Get-Content (Join-Path $bundle 'Tools/Detect-Template.ps1') -Raw
    $template=$template.Replace("Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ClaudePolicyManager'",'$env:CPM_DIAGNOSTIC_ROOT')
    $detect=Join-Path $temp 'Detect.ps1';[IO.File]::WriteAllText($detect,$template)
    $output=& $exe -NoProfile -File $detect 2>&1
    Assert ($LASTEXITCODE -eq 1 -and @($output).Count -eq 0) 'Failed detection emits no success output'
    $log=Join-Path $logs 'ClaudePolicyManager-Detection.log'
    Assert ((Test-Path $log) -and (Get-Content $log -Raw) -match 'Not detected.*Expected manifest') 'Failed detection records a diagnostic log'
    Remove-Item $logs -Recurse -Force
    $output=& $exe -NoProfile -File $detect 2>&1
    Assert ($LASTEXITCODE -eq 1 -and @($output).Count -eq 0) 'Unavailable log destination does not change detection result or output'
    $fallback=Join-Path $env:SystemRoot 'Logs';[void](New-Item -ItemType Directory $fallback -Force)
    $output=& $exe -NoProfile -File $detect 2>&1
    Assert ($LASTEXITCODE -eq 1 -and (Test-Path (Join-Path $fallback 'ClaudePolicyManager-Detection.log'))) 'Detection uses Windows Logs fallback'
    $installed=$env:CPM_DIAGNOSTIC_ROOT;[void](New-Item -ItemType Directory $installed)
    $mockModule=Join-Path $installed 'PolicyEngine.psm1'
    [IO.File]::WriteAllText($mockModule,'function Assert-InstallationHealthy {param($Root)}; Export-ModuleMember -Function *')
    $manifest=Join-Path $installed 'PackageManifest.json'
    @{ConfigurationId='diagnostic-test';Files=@{'PolicyEngine.psm1'=(Get-FileHash $mockModule).Hash.ToLowerInvariant()}} | ConvertTo-Json -Depth 5 | Set-Content $manifest
    [IO.File]::WriteAllText($detect,$template.Replace('__MANIFEST_SHA256__',(Get-FileHash $manifest).Hash.ToLowerInvariant()))
    $output=& $exe -NoProfile -File $detect 2>&1
    Assert ($LASTEXITCODE -eq 0 -and ($output | Out-String) -match 'Detected Claude policy manager: diagnostic-test') 'Successful detection retains exit zero and success output'
    Write-Output "SUCCESS: $script:Count diagnostic checks. Windows CMD execution requires a Windows pilot."
} finally {
    $env:ProgramData=$oldProgramData;$env:SystemRoot=$oldSystemRoot
    Remove-Item Env:CPM_DIAGNOSTIC_ROOT -ErrorAction SilentlyContinue
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
