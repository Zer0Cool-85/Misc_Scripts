@echo off
setlocal
set "RenamePS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "RenamePS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%RenamePS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Install-RenameComputer.ps1" %*
exit /b %errorlevel%
