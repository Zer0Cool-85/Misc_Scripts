[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestBase64)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
try {
    . (Join-Path $env:SETUP_PACKAGE_ROOT 'Core/Setup.Common.ps1')
    . (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
    if (-not [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { throw 'The machine update worker requires SYSTEM.' }
    $request=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64)) | ConvertFrom-Json
    $moduleRoots=@((Join-Path $env:SETUP_PACKAGE_ROOT 'Payloads/Modules'), (Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules'))
    $candidates=@()
    foreach ($base in $moduleRoots) {
        $dir=Join-Path $base 'Microsoft.WinGet.Client'
        if (Test-Path -LiteralPath $dir -PathType Container) {
            $candidates=@(Get-ChildItem -LiteralPath $dir -Filter Microsoft.WinGet.Client.psd1 -File -Recurse | ForEach-Object {
                $data=Import-PowerShellDataFile -LiteralPath $_.FullName
                [pscustomobject]@{ Path=$_.FullName; Version=[version]$data.ModuleVersion }
            } | Sort-Object Version -Descending)
            if ($candidates.Count) { $env:PSModulePath=$base+';'+$env:PSModulePath; break }
        }
    }
    if (-not $candidates.Count) { throw 'Stage Microsoft.WinGet.Client under Payloads/Modules or install a reviewed AllUsers copy before enrollment.' }
    Import-Module -Name $candidates[0].Path -Force -ErrorAction Stop
    Write-EnterpriseLog "WinGet machine scan: module $($candidates[0].Version), source $($request.Source)."
    $apps=@(Microsoft.WinGet.Client\Get-WinGetPackage -Source $request.Source -ErrorAction Stop | Where-Object { $_.IsUpdateAvailable -and $_.Id -notin $request.ExcludeIds })
    $trouble=0; $restart=$false
    foreach ($app in $apps) {
        try {
            Write-EnterpriseLog "Machine upgrade: $($app.Id)"
            $res=$app | Microsoft.WinGet.Client\Update-WinGetPackage -Scope System -Mode Silent -Confirm:$false -ErrorAction Stop
            if ($null -eq $res) { throw 'WinGet returned no install result.' }
            if ([string]$res.Status -ne 'Ok') { throw "Installer returned status '$($res.Status)'." }
            if ($null -ne $res.PSObject.Properties['RebootRequired'] -and $res.RebootRequired) { $restart=$true }
            Write-EnterpriseLog "Machine upgrade result: $($app.Id) = $($res.Status)"
        } catch { $trouble++; Write-EnterpriseLog -Level WARN -Message "Machine update deferred for $($app.Id): $($_.Exception.Message)" }
    }
    Write-EnterpriseLog "Machine scan finished: $($apps.Count) candidate(s), $trouble incomplete."
    if ($trouble) { exit 20001 }
    if ($restart) { exit 3010 }
    exit 0
} catch { if (Get-Command Write-EnterpriseLog -ErrorAction SilentlyContinue) { Write-EnterpriseLog -Level WARN -Message $_.Exception.Message }; exit 20001 }
