#requires -Version 5.1
# Run after editing User-RebootToast.ps1 or Source/Naming.Common.ps1, BEFORE signing.
# Rebuilds both standalone Intune scripts and updates the embedded toast payload.
$ErrorActionPreference = 'Stop'
$encoding = New-Object Text.UTF8Encoding($true)
$commonPath = Join-Path $PSScriptRoot 'Source\Naming.Common.ps1'
$payloadPath = Join-Path $PSScriptRoot 'Source\User-RebootToast.ps1'
$bytes = [IO.File]::ReadAllBytes($payloadPath)
$base64 = [Convert]::ToBase64String($bytes)
$hash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash
$common = [IO.File]::ReadAllText($commonPath)
foreach ($value in @(@('ToastPayloadBase64',$base64), @('ToastPayloadSha256',$hash))) {
    $pattern = '(?m)^\$script:' + $value[0] + ' = ''[^'']*'''
    $match = [regex]::Match($common, $pattern)
    if (-not $match.Success) { throw "Missing embedded payload field: $($value[0])" }
    $replacement = '$script:' + $value[0] + " = '" + $value[1] + "'"
    $common = $common.Replace($match.Value, $replacement)
}
[IO.File]::WriteAllText($commonPath, $common, $encoding)
foreach ($entry in @(@('Requirement','Requirement-RenameComputer.ps1'), @('Detection','Detect-RenameComputer.ps1'))) {
    $path = Join-Path $PSScriptRoot ('Intune\' + $entry[1])
    $text = [IO.File]::ReadAllText($path)
    $offset = $text.IndexOf('# MAIN:')
    if ($offset -lt 0) { throw "Missing entry-point marker in $path" }
    $header = (@('#requires -Version 5.1', '# Standalone Intune upload script; no companion file is needed.', '$ErrorActionPreference = ''Stop''', ('$script:Component = ''' + $entry[0] + "'")) -join "`r`n") + "`r`n"
    [IO.File]::WriteAllText($path, ($header + $common + "`r`n" + $text.Substring($offset)), $encoding)
}
Write-Output 'Updated embedded payload and both standalone Intune scripts. Rebuild the .intunewin and replace both uploaded rule scripts.'
