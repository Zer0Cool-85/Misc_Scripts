# Pure naming/selection helpers can also be used by offline tests.
function Get-ProvisionVendor {
    param([string]$Manufacturer)
    switch -Regex ($Manufacturer.Trim()) {
        '^(Dell|Dell Inc\.?)(\s|$)' { return 'Dell' }
        '^Lenovo(\s|$)' { return 'Lenovo' }
        '^(HP|Hewlett[- ]Packard)(\s|$)' { return 'HP' }
        default { return 'Other' }
    }
}
function Get-DeviceNameValue {
    param([string]$Template,[string]$Prefix,[string]$Site,[string]$Type,
          [string]$Serial,[string]$AssetTag,[string]$Uuid)
    $value = $Template.ToUpperInvariant()
    if (-not $value -or $value -match '[^A-Z0-9{}:-]') { throw 'Name template contains an unsupported character.' }
    if ($value -notmatch '\{(SERIAL|ASSET|HASH)(:[1-9][0-9]?)?\}') { throw 'Include a stable device token: Serial, Asset or Hash. A constant would assign every PC the same name.' }
    foreach ($token in @([regex]::Matches($value,'\{([^{}]+)\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)) {
        $key=$token.Trim('{}'); $width=0
        if ($key -match '^(SERIAL|ASSET|HASH):([1-9][0-9]?)$') { $key=$Matches[1]; $width=[int]$Matches[2] }
        switch ($key) {
            PREFIX { $part=$Prefix }
            SITE   { $part=$Site }
            TYPE   { $part=$Type }
            SERIAL { $part=$Serial }
            ASSET  { $part=$AssetTag }
            HASH   {
                $id=[Guid]::Empty
                if (-not [Guid]::TryParse($Uuid,[ref]$id) -or $id -eq [Guid]::Empty -or $id.ToString('N') -match '^f+$') { throw 'No usable SMBIOS UUID for the HASH token.' }
                $sha=[Security.Cryptography.SHA256]::Create()
                try { $part=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($id.ToString('N'))))).Replace('-','') } finally { $sha.Dispose() }
                if (-not $width) { $width=8 }
                if ($width -lt 4 -or $width -gt 15) { throw 'HASH length must be 4-15.' }
            }
            default { throw "Unknown device name token: $token" }
        }
        if ($key -in @('SERIAL','ASSET')) {
            $part=([string]$part).ToUpperInvariant() -replace '[^A-Z0-9]',''
            if (-not $part -or $part -match '^(0+|F+|NONE|NA|UNKNOWN|DEFAULTSTRING|SYSTEMSERIALNUMBER|TOBEFILLEDBYOEM|NOSERIALNUMBER|NOASSETTAG|NOTSPECIFIED|ASSETTAG|123456789)$') { throw "Unusable firmware value for $token." }
        }
        if (-not $part -or $part -notmatch '^[a-zA-Z0-9-]+$') { throw "Empty or invalid value for $token." }
        if ($width -gt 15) { throw "Maximum token width is 15: $token" }
        if ($width -and $part.Length -gt $width) { if ($key -eq 'HASH') { $part=$part.Substring(0,$width) } else { $part=$part.Substring($part.Length-$width) } }
        $value=$value.Replace($token,$part.ToUpperInvariant())
    }
    if ($value -notmatch '^[A-Z0-9](?:[A-Z0-9-]{0,13}[A-Z0-9])?$' -or $value -match '^\d+$' -or $value -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9]|LOCALHOST)$') {
        throw "Invalid result '$value'. Use 1-15 letters, digits or interior hyphens, with at least one letter. Shorten the template rather than truncating the final name."
    }
    return $value
}
function Get-ProvisionArp {
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($k in Get-ChildItem -LiteralPath $base -ErrorAction Stop) {
            $n=[string]$k.GetValue('DisplayName')
            if ($n) { [pscustomobject]@{ Name=$n; Publisher=[string]$k.GetValue('Publisher'); Id=$k.PSChildName; Key=$k.PSPath; Msi=([string]$k.GetValue('WindowsInstaller') -eq '1'); Quiet=[string]$k.GetValue('QuietUninstallString') } }
        }
    }
}
function Remove-ProvisionAppx {
    param([string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]+$') { throw "Expected an exact package name: $Name" }
    foreach ($p in @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object DisplayName -eq $Name)) {
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
    }
    foreach ($kind in @('Bundle','Main')) {
        $pkgs=@(Get-AppxPackage -AllUsers -Name $Name -PackageTypeFilter $kind -ErrorAction Stop | Where-Object Name -eq $Name | Sort-Object PackageFullName -Unique)
        foreach ($p in $pkgs) { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
    }
    if (@(Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop).Count -or @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object DisplayName -eq $Name).Count) { throw "AppX removal did not verify: $Name" }
}
function Get-OfficeDesktopEvidence {
    # Detection only. Never execute an ARP uninstall string or use Win32_Product.
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration')) {
        if (Test-Path -LiteralPath $base) {
            $ids=[string](Get-Item -LiteralPath $base -ErrorAction Stop).GetValue('ProductReleaseIds')
            if ($ids.Trim()) { "C2R: $ids" }
        }
    }
    foreach ($a in Get-ProvisionArp) {
        if ($a.Publisher -notmatch '^Microsoft (Corporation|Corp\.?)$') { continue }
        if ($a.Name -match '(?i)( add[- ]?in| redistributable| update for | runtime| access database engine| connectivity components| developer tools| file validation| extensibility| primary interop| visual studio| meeting add| teams meeting| click-to-run [a-z]+ component| language pack for visual studio)') { continue }
        if ($a.Name -match '^(Microsoft (365( Apps| -| Business| Enterprise| Personal| Family| [a-z]{2}-)|Office($| (365|XP|Professional|Standard|Enterprise|Home|Small Business|Basic|Starter|Ultimate|Personal|LTSC|[12][0-9]{3}|Word|Excel|PowerPoint|Outlook|Access|Publisher|OneNote|Project|Visio|Proofing|Language)))|Microsoft (Word|Excel|PowerPoint|Outlook|Access|Publisher|OneNote|Visio|Project)( |$))') { "ARP: $($a.Name)" }
    }
    foreach ($base in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) | Where-Object { $_ } | Select-Object -Unique) {
        foreach ($version in @('Office','Office10','Office11','Office12','Office14','Office15','Office16','root\Office15','root\Office16')) {
            foreach($exe in @('WINWORD','EXCEL','POWERPNT','OUTLOOK','MSACCESS','MSPUB','ONENOTE','VISIO','WINPROJ')) {
                $path=Join-Path $base ("Microsoft Office\{0}\{1}.EXE" -f $version,$exe)
                if (Test-Path -LiteralPath $path -PathType Leaf) { "File: $path" }
            }
        }
    }
}
function Get-EncryptionVerdict {
    param([string]$Status,[string]$Protection,[bool]$AllowInProgress)
    if ($Status -eq 'FullyEncrypted' -and $Protection -eq 'On') { return 'Protected' }
    if ($Status -eq 'EncryptionInProgress' -and $Protection -eq 'On' -and $AllowInProgress) { return 'Encrypting' }
    return 'NeedsAttention'
}
