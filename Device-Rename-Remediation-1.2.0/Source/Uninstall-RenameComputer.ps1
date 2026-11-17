#requires -Version 5.1
# Removes machine receipt, notification tasks and helper. No name rollback.
# Per-user registrations can be removed first with User-RebootToast.ps1 -Mode Cleanup.
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use Uninstall.cmd to launch 64-bit Windows PowerShell.' }
    $tasks = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -like 'DeviceRename-RebootToast-*' })
    foreach ($task in $tasks) {
        if ($task.State -eq 'Running') { Stop-ScheduledTask -InputObject $task -ErrorAction Stop }
        Unregister-ScheduledTask -InputObject $task -Confirm:$false -ErrorAction Stop
    }
    $key = 'HKLM:\SOFTWARE\DeviceRenameRemediation'
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop }
    $directory = Join-Path $env:ProgramFiles 'DeviceRenameRemediation'
    if (Test-Path -LiteralPath $directory) {
        $folder = Get-Item -LiteralPath $directory -ErrorAction Stop
        if (($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing cleanup through a reparse point.' }
        $helper = Join-Path $directory 'User-RebootToast.ps1'
        if (Test-Path -LiteralPath $helper) { Remove-Item -LiteralPath $helper -Force -ErrorAction Stop }
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { Remove-Item -LiteralPath $directory -Force }
    }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
