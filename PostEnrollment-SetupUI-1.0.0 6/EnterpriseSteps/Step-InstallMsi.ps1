[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsiRelativePath,
    [Parameter(Mandatory)][ValidatePattern('^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$')][string]$ProductCode,
    [string]$MinimumVersion = '',
    [string[]]$Properties = @(),
    [string]$ExpectedSha256 = '',
    [bool]$RequireValidSignature = $true,
    [bool]$AppendVerboseLogToPrimary = $true,
    [ValidateRange(0,10)][int]$BusyRetries = 3,
    [ValidateRange(5,120)][int]$BusyRetrySeconds = 30
)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
function Test-MsiInstalled {
    foreach ($key in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode")) {
        if (Test-Path -LiteralPath $key) {
            $entry = Get-ItemProperty -LiteralPath $key
            if (-not $MinimumVersion) { return $true }
            if ($null -ne $entry.PSObject.Properties['DisplayVersion'] -and [version]$entry.DisplayVersion -ge [version]$MinimumVersion) { return $true }
        }
    }
    return $false
}
try {
    if ($ProductCode -eq '{00000000-0000-0000-0000-000000000000}') { throw 'Replace the example ProductCode with the real MSI ProductCode before running live.' }
    if (Test-MsiInstalled) { Set-EnterpriseProgress "MSI $ProductCode already meets detection requirements."; return }
    $msi = Resolve-EnterpriseFile $MsiRelativePath
    if ($ExpectedSha256 -and (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $ExpectedSha256) { throw 'MSI SHA256 mismatch.' }
    if ($RequireValidSignature -and (Get-AuthenticodeSignature -LiteralPath $msi).Status -ne 'Valid') { throw 'MSI signature validation failed. Approve/sign the package or explicitly configure the unsigned-package exception.' }
    foreach ($property in $Properties) {
        if ($property -cnotmatch '^[A-Z][A-Z0-9_]*=(?:[^"\s\r\n]*|"[^"\r\n]*")$' -or $property -match '^(REBOOT|ALLUSERS|MSIINSTALLPERUSER)=') {
            throw 'Use NAME=value or NAME="quoted value" MSI properties. Scope/reboot properties are controlled by this script.'
        }
    }
    for ($attempt = 0; $attempt -le $BusyRetries; $attempt++) {
        $verboseLog = Join-Path $env:SETUP_RUN_DIRECTORY ('{0}-MSI-{1}-{2}.log' -f $env:SETUP_STEP_ID, [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'), $attempt)
        Set-EnterpriseProgress "Installing MSI $ProductCode (attempt $($attempt + 1)). Native log: $verboseLog"
        $arguments = '/i "{0}" /qn /norestart /L*v "{1}" ALLUSERS=1 REBOOT=ReallySuppress {2}' -f $msi, $verboseLog, ($Properties -join ' ')
        $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
        $code = $process.ExitCode
        Write-EnterpriseLog "MSI exit code: $code."
        if ($AppendVerboseLogToPrimary -and (Test-Path -LiteralPath $verboseLog)) {
            Write-EnterpriseLog "BEGIN MSI verbose log: $verboseLog"
            # MSI's native log remains intact. Merge it only after msiexec closes it.
            Get-Content -LiteralPath $verboseLog | ForEach-Object { Write-EnterpriseLog -Level MSI -Message $_ }
            Write-EnterpriseLog 'END MSI verbose log.'
        }
        if ($code -eq 1618 -and $attempt -lt $BusyRetries) {
            Set-EnterpriseProgress "Another installer is busy; retrying in $BusyRetrySeconds seconds."
            Start-Sleep -Seconds $BusyRetrySeconds
            continue
        }
        if ($code -notin @(0,3010)) { throw "MSI failed with exit code $code. See $verboseLog" }
        if ($code -eq 3010) { $global:SetupUiRebootRequired = $true }
        if (-not (Test-MsiInstalled)) { throw "Installer returned $code but product/version detection failed for $ProductCode." }
        Set-EnterpriseProgress 'MSI installation verified.'
        return
    }
}
catch { Write-EnterpriseLog -Level ERROR -Message $_.Exception.Message; throw }
