# Each step gets a fresh, hidden PowerShell process. This is not the UI process.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Setup.Common.ps1')
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$transcriptStarted = $false
$result = [ordered]@{ ExitCode = 0; Error = ''; FinishedUtc = '' }
try {
    Start-Transcript -LiteralPath $request.LogPath -Force | Out-Null
    $transcriptStarted = $true
    $env:SETUP_PACKAGE_ROOT = $request.PackageRoot
    $env:SETUP_STEP_ID = $request.StepId
    $env:SETUP_RUN_DIRECTORY = $request.RunDirectory
    $env:SETUP_PROGRESS_FILE = $request.ProgressPath

    function Write-SetupProgress {
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Message, [ValidateRange(0,100)][int]$Percent = -1)
        $p = [ordered]@{ Message = $Message; Percent = $Percent; UpdatedUtc = [DateTime]::UtcNow.ToString('o') }
        Write-SetupJson -Path $env:SETUP_PROGRESS_FILE -Value $p
        Write-Host $Message
    }

    function Invoke-SetupProcess {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$FilePath,
            [string]$Arguments = '',
            [int[]]$SuccessExitCodes = @(0,3010),
            [int[]]$RebootExitCodes = @(3010)
        )
        $p = @{ FilePath = $FilePath; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
        if ($Arguments) { $p.ArgumentList = $Arguments }
        $process = Start-Process @p
        if ($process.ExitCode -notin $SuccessExitCodes) { throw "Installer '$FilePath' exited with code $($process.ExitCode)." }
        if ($process.ExitCode -in $RebootExitCodes) { $global:SetupUiRebootRequired = $true }
        return $process.ExitCode
    }

    $parameters = @{}
    foreach ($property in $request.Parameters.PSObject.Properties) { $parameters[$property.Name] = $property.Value }
    $global:SetupUiRebootRequired = $false
    $global:LASTEXITCODE = 0
    # A normal return means success. Do not return booleans as a status protocol.
    & $request.ScriptPath @parameters
    # A nested script's 'exit N' can return to this caller and set LASTEXITCODE.
    # Also preserve an unchecked native executable's final nonzero exit code.
    if ($LASTEXITCODE -ne 0) { $result.ExitCode = [int]$LASTEXITCODE }
    elseif ($global:SetupUiRebootRequired) { $result.ExitCode = 3010 }
}
catch {
    $result.ExitCode = 1
    $result.Error = $_.Exception.Message + [Environment]::NewLine + $_.ScriptStackTrace
    Write-Host $result.Error
}
finally {
    $result.FinishedUtc = [DateTime]::UtcNow.ToString('o')
    try { Write-SetupJson -Path $request.ResultPath -Value $result } catch { Write-Host $_ }
    if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
}
exit ([int]$result.ExitCode)
