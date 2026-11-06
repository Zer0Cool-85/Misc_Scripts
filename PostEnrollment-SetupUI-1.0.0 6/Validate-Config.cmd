@echo off
setlocal
set "SetupPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "SetupPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%SetupPowerShell%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DeviceSetup.ps1" -ValidateOnly
set "SetupResult=%errorlevel%"
pause
exit /b %SetupResult%
