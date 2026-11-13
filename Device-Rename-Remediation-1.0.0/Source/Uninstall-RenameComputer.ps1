#requires -Version 5.1
# Removes only this app's receipt/reminder state. A rename has no automatic rollback.
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use Uninstall.cmd to launch 64-bit Windows PowerShell.' }
    $key = 'HKLM:\SOFTWARE\DeviceRenameRemediation'
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
