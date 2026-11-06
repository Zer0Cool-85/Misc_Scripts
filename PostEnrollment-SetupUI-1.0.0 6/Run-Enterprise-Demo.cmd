@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Start-DeviceSetup.ps1" -ConfigPath "%~dp0Config\Enterprise-Example.json" -Demo
exit /b %errorlevel%
