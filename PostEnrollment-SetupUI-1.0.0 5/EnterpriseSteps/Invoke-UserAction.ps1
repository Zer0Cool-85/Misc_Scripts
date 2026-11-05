[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestBase64)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$wingetLogDirectory = $null
$wingetProcess = $null
$wingetCancellationUncertain = $false
try {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { throw 'User action must run as the interactive user.' }
    $request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64)) | ConvertFrom-Json
    switch ($request.Action) {
        'InstallStoreWithWinGet' {
            if ($request.PackageId -notin @('9WZDNCRFJ3PZ','9MSMLRH6LZF3')) { throw 'Unapproved Store package ID.' }
            if ($request.AttemptId -notmatch '^[0-9a-f]{32}$') { throw 'Invalid WinGet attempt ID.' }
            $timeoutSeconds = [int]$request.WinGetTimeoutSeconds
            if ($timeoutSeconds -lt 30 -or $timeoutSeconds -gt 1200) { throw 'WinGet timeout must be 30-1200 seconds.' }
            $wingetLogDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('PostEnrollmentSetupUI\WinGet\' + $request.AttemptId)
            [void][IO.Directory]::CreateDirectory($wingetLogDirectory)
            $actionLog = Join-Path $wingetLogDirectory 'Action.log'
            Add-Content -LiteralPath $actionLog -Encoding UTF8 -Value ("{0} Target {1}; user SID {2}" -f [DateTime]::Now.ToString('o'), $request.PackageId, [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            # Resolve only this user's registered Microsoft App Installer package;
            # do not search arbitrary PATH entries or another user's WindowsApps.
            $wingetPath = $null
            $installers = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop | Where-Object {
                $_.PackageFamilyName -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -and $_.Status -eq 'Ok' -and
                $_.Publisher -match 'O=Microsoft Corporation(?:,|$)'
            } | Sort-Object Version -Descending)
            foreach ($installer in $installers) {
                if (-not $installer.InstallLocation) { continue }
                $candidate = Join-Path $installer.InstallLocation 'winget.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $wingetPath = $candidate; break }
            }
            if (-not $wingetPath) { throw 'WinGet is not available in a healthy App Installer registration for this user.' }
            $arguments = 'install --id {0} --source msstore --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --authentication-mode silent --log "{1}"' -f $request.PackageId, (Join-Path $wingetLogDirectory 'WinGet.log')
            Add-Content -LiteralPath $actionLog -Encoding UTF8 -Value ("Executable: {0}`r`nArguments: {1}" -f $wingetPath, $arguments)
            $wingetProcess = Start-Process -FilePath $wingetPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop -RedirectStandardOutput (Join-Path $wingetLogDirectory 'stdout.log') -RedirectStandardError (Join-Path $wingetLogDirectory 'stderr.log')
            $null = $wingetProcess.Handle
            if (-not $wingetProcess.WaitForExit($timeoutSeconds * 1000)) {
                $wingetCancellationUncertain = $true
                Add-Content -LiteralPath $actionLog -Encoding UTF8 -Value 'WinGet timeout; stopping the launched process tree.'
                $killer = Start-Process -FilePath "$env:SystemRoot\System32\taskkill.exe" -ArgumentList ("/PID {0} /T /F" -f $wingetProcess.Id) -WindowStyle Hidden -PassThru -ErrorAction Stop
                $null = $killer.Handle
                $killFinished = $killer.WaitForExit(15000)
                if (-not $killFinished -or $killer.ExitCode -ne 0 -or -not $wingetProcess.WaitForExit(5000)) {
                    Add-Content -LiteralPath $actionLog -Encoding UTF8 -Value 'Cancellation could not be confirmed; return 12001 to prevent concurrent offline fallback.'
                    exit 12001
                }
                $wingetCancellationUncertain = $false
                Add-Content -LiteralPath $actionLog -Encoding UTF8 -Value 'WinGet process tree stopped; return 1460 (timeout).'
                exit 1460
            }
            $wingetProcess.WaitForExit()
            if ($null -eq $wingetProcess.ExitCode) { throw 'WinGet finished but its native exit code was unavailable.' }
            $nativeCode = [int]$wingetProcess.ExitCode
            Add-Content -LiteralPath $actionLog -Encoding UTF8 -Value ("{0} WinGet exit code: {1}" -f [DateTime]::Now.ToString('o'), $nativeCode)
            exit $nativeCode
        }
        'InstallAppx' {
            $args = @{Path=[string]$request.PackagePath; ErrorAction='Stop'}
            if (@($request.Dependencies).Count) { $args.DependencyPath = [string[]]$request.Dependencies }
            Add-AppxPackage @args
        }
        'UninstallOneDrive' {
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe'
            if (-not (Test-Path $key)) { exit 0 }
            $command = [string](Get-ItemProperty -LiteralPath $key -Name UninstallString).UninstallString
            if ($command -notmatch '^"(?<exe>[^"\r\n]+OneDriveSetup\.exe)"\s+/uninstall(?:\s+.*)?$') { throw 'Unrecognized per-user OneDrive uninstaller command.' }
            $exe = $Matches.exe
            $sig = Get-AuthenticodeSignature -LiteralPath $exe
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') { throw 'OneDrive uninstaller signature is not valid Microsoft.' }
            $p = Start-Process -FilePath $exe -ArgumentList '/uninstall' -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "OneDrive uninstall exit code: $($p.ExitCode)" }
        }
        default { throw 'Unknown user action.' }
    }
    exit 0
}
catch {
    $failureMessage = $_.Exception.Message
    $exitCode = if ($wingetCancellationUncertain) { 12001 } else { 1 }
    # An exception after launch (including a taskkill/logging failure) must not
    # silently allow offline deployment beside a process that may still run.
    if ($null -ne $wingetProcess) {
        try { if (-not $wingetProcess.HasExited) { $exitCode = 12001 } }
        catch { $exitCode = 12001 }
    }
    if ($wingetLogDirectory) {
        try { Add-Content -LiteralPath (Join-Path $wingetLogDirectory 'Action.log') -Value ("{0} ERROR: {1}; helper exit {2}" -f [DateTime]::Now.ToString('o'), $failureMessage, $exitCode) -Encoding UTF8 } catch { }
    }
    try { Add-Content -LiteralPath (Join-Path $env:TEMP 'PostEnrollment-UserAction.log') -Value ("{0} {1}" -f [DateTime]::Now.ToString('o'), $failureMessage) -Encoding UTF8 } catch { }
    exit $exitCode
}
