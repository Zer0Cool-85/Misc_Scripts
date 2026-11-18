@echo off
setlocal
set "CPM_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "CPM_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "CPM_LOGDIR=%ProgramData%\Microsoft\IntuneManagementExtension\Logs"
if not exist "%CPM_LOGDIR%\." set "CPM_LOGDIR=%SystemRoot%\Logs"
set "CPM_LOG=%CPM_LOGDIR%\ClaudePolicyManager-Uninstall.log"
>>"%CPM_LOG%" echo ===== Uninstall %DATE% %TIME% =====
if errorlevel 1 goto NoFileLog
echo Diagnostic log: "%CPM_LOG%"
>>"%CPM_LOG%" echo Source="%~dp0"
>>"%CPM_LOG%" echo PowerShell="%CPM_PS%"
"%SystemRoot%\System32\whoami.exe" >>"%CPM_LOG%" 2>&1
"%CPM_PS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Uninstall-PolicyManager.ps1" %* >>"%CPM_LOG%" 2>&1
set "CPM_RC=%errorlevel%"
>>"%CPM_LOG%" echo ExitCode=%CPM_RC%
exit /b %CPM_RC%
:NoFileLog
echo Cannot write diagnostic log "%CPM_LOG%". Continuing with console output.
"%CPM_PS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Uninstall-PolicyManager.ps1" %*
exit /b %errorlevel%
