[CmdletBinding()]
param([ValidateSet('Audit','Remove')][string]$Mode='Audit', [string]$CatalogRelativePath='Catalogs/OemCleanup.json')
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
. (Join-Path $PSScriptRoot 'Provisioning.Common.ps1')
$vendor=Get-ProvisionVendor ([string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer)
if ($vendor -eq 'Other') { Set-EnterpriseProgress 'No cleanup profile for this manufacturer; nothing changed.'; return }
$catalog=Get-Content -Raw -Encoding UTF8 -LiteralPath (Resolve-EnterpriseFile $CatalogRelativePath) | ConvertFrom-Json
$profile=$catalog.PSObject.Properties[$vendor]
if (-not $profile) { throw "Catalog lacks an entry for $vendor." }
$rules=$profile.Value
foreach ($field in @('Appx','Programs','Publishers')) {
    if ($null -eq $rules.PSObject.Properties[$field] -or $rules.$field -isnot [Array]) { throw "Invalid $vendor catalog field: $field" }
    foreach ($v in $rules.$field) { if ($v -isnot [string] -or -not $v.Trim() -or $v -match '[*?\[\]]') { throw "Use only exact names in $field." } }
}
$apps=@(Get-AppxPackage -AllUsers -ErrorAction Stop | Select-Object -ExpandProperty Name)
$prov=@(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Select-Object -ExpandProperty DisplayName)
$appx=@($rules.Appx | Where-Object { $_ -in $apps -or $_ -in $prov } | Sort-Object -Unique)
$vendorPrograms=@(Get-ProvisionArp | Where-Object { $_.Publisher -in $rules.Publishers })
$programs=@($vendorPrograms | Where-Object { $_.Name -in $rules.Programs })
$prefix= switch ($vendor) {
    'Dell' { '^(DellInc\.|4DF9E0F8\.)' }
    'Lenovo' { '^E046963F\.' }
    'HP' { '^AD2F1837\.' }
}
Write-SetupJson (Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID+'-Inventory.json')) ([ordered]@{
    Manufacturer=$vendor; Mode=$Mode; MatchedAppx=$appx; MatchedPrograms=@($programs | Select-Object -ExpandProperty Name)
    VendorPrograms=@($vendorPrograms | Select-Object -Property @('Name','Publisher','Id','Msi')); VendorRegisteredAppx=@($apps | Where-Object { $_ -match $prefix } | Sort-Object -Unique)
    VendorProvisionedAppx=@($prov | Where-Object { $_ -match $prefix } | Sort-Object -Unique)
})
Set-EnterpriseProgress "$vendor cleanup ($Mode): $($appx.Count) AppX name(s), $($programs.Count) machine uninstall record(s) matched."
foreach ($n in $appx) { Write-EnterpriseLog "Matched $vendor AppX: $n" }
foreach ($p in $programs) { Write-EnterpriseLog "Matched $vendor desktop app: $($p.Name) [$($p.Publisher)]" }
if ($Mode -eq 'Audit') { $global:SetupUiStepSummary="$vendor inventory: $($appx.Count) AppX name(s), $($programs.Count) desktop record(s) matched."; return }
$issues=@()
foreach ($n in $appx) {
    try { Set-EnterpriseProgress "Removing $n"; Remove-ProvisionAppx $n } catch { $issues+="$n - $($_.Exception.Message)" }
}
foreach ($p in $programs) {
    try {
        if (-not (Test-Path -LiteralPath $p.Key)) { continue }
        Set-EnterpriseProgress "Removing $($p.Name)"
        if ($p.Msi -and $p.Id -match '^\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}$') {
            $log=Join-Path $env:SETUP_RUN_DIRECTORY ($env:SETUP_STEP_ID+'-'+$p.Id+'.log')
            Invoke-SetupProcess (Join-Path $env:SystemRoot 'System32\msiexec.exe') ('/x {0} /qn /norestart /L*v "{1}"' -f $p.Id,$log) -SuccessExitCodes @(0,1605,1614,3010) | Out-Null
        } else {
            # ARP is data, not executable script. Only a signed, protected vendor EXE
            # with a known unattended command shape may be launched. No shell.
            if ($p.Quiet -notmatch '^\s*"(?<path>[A-Za-z]:\\[^"\r\n]+\.exe)"\s+(?<arguments>[^"\r\n]+)\s*$') { throw 'No supported quoted QuietUninstallString. Package this EXE explicitly.' }
            $exe=[IO.Path]::GetFullPath($Matches.path);$arguments=$Matches.arguments.Trim()
            $roots=@($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) | Where-Object { $_ -and $exe.StartsWith(($_.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) }
            if (-not $roots -or [IO.Path]::GetFileName($exe) -notmatch '^(unins[0-9]+|uninstall(?:er)?|setup)\.exe$') { throw 'Unrecognized vendor uninstall path.' }
            $tokens=@($arguments -split '\s+')
            foreach ($t in $tokens) { if ($t -notmatch '^[-/]{1,2}(s|silent|verysilent|quiet|qn|norestart|suppressmsgboxes|uninstall|remove|sp-)$') { throw 'Unreviewed uninstall arguments. Package this EXE explicitly.' } }
            if (-not @($tokens | Where-Object { $_ -match '^[-/]{1,2}(s|silent|verysilent|quiet|qn)$' }).Count) { throw 'No unattended switch.' }
            $signature=Get-AuthenticodeSignature -LiteralPath $exe
            $org= switch ($vendor) {
                'Dell' { 'Dell (Inc\.?|Technologies Inc\.?)' }
                'HP' { '(HP Inc\.?|Hewlett-Packard Company)' }
                'Lenovo' { 'Lenovo(?: Group (?:Limited|Ltd\.?)| \(United States\)(?: Inc\.?)?)?' }
            }
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch ("(?:^|,\s*)O=("+$org+")(?=,|$)")) { throw 'EXE publisher signature does not match the selected manufacturer.' }
            Invoke-SetupProcess -FilePath $exe -Arguments $arguments | Out-Null
        }
        if (Test-Path -LiteralPath $p.Key) { throw 'Uninstall entry remains after the command returned.' }
    } catch { $issues+="$($p.Name) - $($_.Exception.Message)" }
}
if ($issues.Count) { foreach ($i in $issues) { Write-EnterpriseLog -Level WARN -Message $i }; throw ('Some matched OEM apps need review: '+($issues -join '; ')) }
Set-EnterpriseProgress "$vendor cleanup verified."
