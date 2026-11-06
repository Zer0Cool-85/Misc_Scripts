@echo off
setlocal
rem Run this from your existing SYSTEM deployment/logon workflow.
rem ServiceUI does not elevate a standard user to SYSTEM.
if not exist "%~dp0Tools\ServiceUI.exe" (
  echo Place your existing x64 ServiceUI.exe in the Tools folder.
  exit /b 2
)
set "SetupPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
rem The x64 ServiceUI process resolves System32 to the 64-bit directory.
rem Do not pass a Sysnative path to an x64 ServiceUI process.
"%~dp0Tools\ServiceUI.exe" -process:explorer.exe "%SetupPowerShell%" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Start-DeviceSetup.ps1" -ConfigPath "%~dp0Config\Setup.json" -Live
exit /b %errorlevel%
