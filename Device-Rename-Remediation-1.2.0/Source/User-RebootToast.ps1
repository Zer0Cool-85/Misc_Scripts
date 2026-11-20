#requires -Version 5.1
<# Runs only in the interactive user's Windows PowerShell 5.1 session.
   Show submits one native toast and exits. Windows implements Snooze.
   Activate handles only the exact protocol routes and current random token.
   Cleanup removes this user's toast registration and shortcut, not the name.
#>
[CmdletBinding()]
param(
    [ValidateSet('Show','Activate','Cleanup')][string]$Mode = 'Show',
    [string]$ActivationUri,
    [switch]$Preview,
    [string]$ExpectedSid,
    [int]$ExpectedSessionId
)
$ErrorActionPreference = 'Stop'
$script:AppId = 'DeviceRenameRemediation.Reboot'
$script:Protocol = 'devicerename-reboot'
$script:UserRoot = 'HKCU:\Software\DeviceRenameRemediation\Toast'
$script:DisplayName = 'IT Device Setup'
$script:ToastStage = 'starting user helper'

function Write-ToastLog {
    param([string]$Message)
    try {
        $directory = Join-Path $env:LOCALAPPDATA 'DeviceRenameRemediation'
        if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -Path $directory -ItemType Directory) }
        Add-Content -LiteralPath (Join-Path $directory 'Toast.log') -Encoding UTF8 -Value ("$([DateTime]::UtcNow.ToString('o')) build=1.2.3 pid=$PID mode=$Mode $Message")
    } catch { }
}

function Get-ToastNameState {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
    $active = [string](Get-ItemPropertyValue -LiteralPath "$key\ActiveComputerName" -Name ComputerName -ErrorAction Stop)
    $target = [string](Get-ItemPropertyValue -LiteralPath "$key\ComputerName" -Name ComputerName -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace($active) -or [string]::IsNullOrWhiteSpace($target)) { throw 'Computer-name state is unavailable.' }
    [pscustomobject]@{ Active=$active; Target=$target; Pending=($active -ine $target) }
}

function Read-ToastRecord {
    if (-not (Test-Path -LiteralPath $script:UserRoot)) { return $null }
    $properties = Get-ItemProperty -LiteralPath $script:UserRoot -ErrorAction Stop
    $value = $properties.PSObject.Properties['Current']
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value.Value)) { return $null }
    try { return ($value.Value | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Save-ToastRecord {
    param([Parameter(Mandatory)]$Record)
    if (-not (Test-Path -LiteralPath $script:UserRoot)) { [void](New-Item -Path $script:UserRoot -Force) }
    [void](New-ItemProperty -LiteralPath $script:UserRoot -Name Current -PropertyType String -Value ($Record | ConvertTo-Json -Compress) -Force)
}

function Test-RestartAuthorization {
    param($Record, $NameState, [string]$Token, [long]$NowTicks = [DateTime]::UtcNow.Ticks)
    if ($null -eq $Record -or $null -eq $NameState) { return $false }
    if ($Token -cnotmatch '\A[a-f0-9]{32}\z' -or $Record.Token -cne $Token) { return $false }
    if ($Record.Preview -ne $false -or $Record.Consumed -ne $false) { return $false }
    $expires = [long]0
    if (-not [long]::TryParse([string]$Record.ExpiresTicks, [ref]$expires) -or $expires -le $NowTicks) { return $false }
    return ($NameState.Pending -and $NameState.Active -ieq $Record.Active -and $NameState.Target -ieq $Record.Target)
}

function Get-ToastActivation {
    param([string]$Uri)
    # No arbitrary command, path, arguments, or URI query is ever executed.
    if ($Uri -cmatch '\Adevicerename-reboot://(restart|open)/([a-f0-9]{32})/?\z') {
        return [pscustomobject]@{ Action=$Matches[1]; Token=$Matches[2] }
    }
    return $null
}

function New-RenameToastXml {
    param([Parameter(Mandatory)][string]$Token, [switch]$IsPreview)
    if ($Token -cnotmatch '\A[a-f0-9]{32}\z') { throw 'Invalid toast token.' }
    $title = 'Restart required'
    $body = 'Your PC needs a restart to finish a device-name update. Save your work before choosing Restart now.'
    if ($IsPreview) { $title = 'Preview: restart reminder'; $body = 'This is a test notification. Restart now is disabled in this preview; Snooze can be tested normally.' }
    $title = [Security.SecurityElement]::Escape($title)
    $body = [Security.SecurityElement]::Escape($body)
    return @"
<toast scenario="reminder" activationType="protocol" launch="devicerename-reboot://open/$Token">
  <visual><binding template="ToastGeneric"><text>$title</text><text>$body</text></binding></visual>
  <actions>
    <input id="snoozeTime" type="selection" title="Remind me in" defaultInput="15">
      <selection id="15" content="15 minutes" />
      <selection id="60" content="1 hour" />
      <selection id="240" content="4 hours" />
    </input>
    <action content="Snooze" activationType="system" arguments="snooze" hint-inputId="snoozeTime" />
    <action content="Restart now" activationType="protocol" arguments="devicerename-reboot://restart/$Token" />
  </actions>
  <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@
}

function Initialize-ShortcutInterop {
    if ('DeviceRenameToast.ShortcutProperties' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace DeviceRenameToast {
    [StructLayout(LayoutKind.Sequential)]
    public struct PropertyKey { public Guid FormatId; public uint Id; }
    [StructLayout(LayoutKind.Explicit, Size=24)]
    public struct PropVariant {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Pointer;
    }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }
    public static class ShortcutProperties {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
        private static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr binding,
            uint flags, ref Guid interfaceId, out IPropertyStore store);
        [DllImport("ole32.dll", ExactSpelling=true)]
        private static extern int PropVariantClear(ref PropVariant value);
        public static void Set(string shortcut, string appId, string activatorId) {
            Guid iid = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreFromParsingName(shortcut, IntPtr.Zero, 2, ref iid, out store));
            try {
                var key = new PropertyKey { FormatId=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Id=5 };
                var value = new PropVariant { Type=31, Pointer=Marshal.StringToCoTaskMemUni(appId) };
                try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value)); }
                finally { PropVariantClear(ref value); }
                // A stub CLSID permits protocol-activated notifications to persist.
                key.Id = 26;
                value = new PropVariant { Type=72, Pointer=Marshal.AllocCoTaskMem(16) };
                try {
                    Marshal.Copy(new Guid(activatorId).ToByteArray(), 0, value.Pointer, 16);
                    Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value));
                } finally { PropVariantClear(ref value); }
                Marshal.ThrowExceptionForHR(store.Commit());
            } finally { Marshal.ReleaseComObject(store); }
        }
    }
}
'@ | Out-Null
}

function Register-ToastIdentity {
    $script:ToastStage = 'register notification identity'
    Initialize-ShortcutInterop
    $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = $PSCommandPath
    $command = '"{0}" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -Mode Activate -ActivationUri "%1"' -f $powerShell, $scriptPath
    $protocolKey = 'HKCU:\Software\Classes\' + $script:Protocol
    foreach ($path in @($protocolKey, "$protocolKey\shell", "$protocolKey\shell\open", "$protocolKey\shell\open\command")) {
        if (-not (Test-Path -LiteralPath $path)) { [void](New-Item -Path $path -Force) }
    }
    Set-Item -LiteralPath $protocolKey -Value 'URL:Device rename restart reminder'
    [void](New-ItemProperty -LiteralPath $protocolKey -Name 'URL Protocol' -PropertyType String -Value '' -Force)
    Set-Item -LiteralPath "$protocolKey\shell\open\command" -Value $command
    $identity = 'HKCU:\Software\Classes\AppUserModelId\' + $script:AppId
    if (-not (Test-Path -LiteralPath $identity)) { [void](New-Item -Path $identity -Force) }
    [void](New-ItemProperty -LiteralPath $identity -Name DisplayName -PropertyType String -Value $script:DisplayName -Force)
    $script:ToastStage = 'create Start menu shortcut'
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'IT Device Restart.lnk'
    $shell = New-Object -ComObject WScript.Shell
    if ($null -eq $shell) { throw 'WScript.Shell returned no COM object.' }
    $shortcut = $null
    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        if ($null -eq $shortcut) { throw "WScript.Shell returned no shortcut for $shortcutPath." }
        $shortcut.TargetPath = $powerShell
        $shortcut.Arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Show' -f $scriptPath
        $shortcut.Description = 'Show the pending computer rename restart reminder'
        $shortcut.IconLocation = "$env:WINDIR\System32\shell32.dll,238"
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
    $script:ToastStage = 'set shortcut notification identity'
    [DeviceRenameToast.ShortcutProperties]::Set($shortcutPath, $script:AppId, 'F4BD91B1-4ED5-4E18-9B2E-6F8F9BF78856')
}

function Initialize-ToastRuntime {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
    [void][Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType=WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
}

function Remove-RenameToast {
    try { Initialize-ToastRuntime; [Windows.UI.Notifications.ToastNotificationManager]::History.Clear($script:AppId) } catch { Write-ToastLog "Clear toast: $($_.Exception.Message)" }
}

function Send-RenameToast {
    param($Notifier, $Toast)
    if ($null -eq $Notifier) { throw "Windows returned no toast notifier for $script:AppId." }
    if ($null -eq $Toast) { throw 'Windows returned no toast notification object.' }
    $script:ToastStage = 'read notification setting'
    $setting = $Notifier.Setting
    if ($null -eq $setting) {
        Write-ToastLog 'Notification setting unavailable. Submitting through the Windows notifier.'
    } elseif ([string]$setting -notin 'Enabled','0') {
        throw "Windows notification setting for $script:AppId is $setting."
    }
    $script:ToastStage = 'submit toast to Windows'
    $Notifier.Show($Toast)
}

function Show-RenameToast {
    param([switch]$IsPreview)
    $script:ToastStage = 'read computer name state'
    $state = Get-ToastNameState
    if (-not $state.Pending -and -not $IsPreview) {
        Remove-RenameToast
        Write-ToastLog 'No pending computer rename; nothing to display.'
        return
    }
    Register-ToastIdentity
    $script:ToastStage = 'load Windows notification types'
    Initialize-ToastRuntime
    $token = [Guid]::NewGuid().ToString('N')
    $expires = [DateTime]::UtcNow.AddDays(1)
    $script:ToastStage = 'save activation record'
    Save-ToastRecord ([pscustomobject]@{ Token=$token; Active=$state.Active; Target=$state.Target; Preview=[bool]$IsPreview; Consumed=$false; ExpiresTicks=$expires.Ticks.ToString() })
    $script:ToastStage = 'build toast XML'
    $xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
    if ($null -eq $xml) { throw 'Windows returned no XML document.' }
    $xml.LoadXml((New-RenameToastXml -Token $token -IsPreview:$IsPreview))
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    if ($null -eq $toast) { throw 'Windows returned no toast notification object.' }
    $toast.Tag = 'rename'
    $toast.Group = 'device-setup'
    $toast.ExpirationTime = [DateTimeOffset]$expires
    $toast.ExpiresOnReboot = $true
    $script:ToastStage = 'create Windows notifier'
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($script:AppId)
    Send-RenameToast -Notifier $notifier -Toast $toast
    Write-ToastLog "Toast submitted; preview=$([bool]$IsPreview); target=$($state.Target)."
}

function Invoke-ToastActivation {
    param([string]$Uri)
    $activation = Get-ToastActivation -Uri $Uri
    if ($null -eq $activation) { throw 'Unsupported activation URI.' }
    $record = Read-ToastRecord
    if ($null -eq $record -or $record.Token -cne $activation.Token) { Write-ToastLog 'Ignoring obsolete toast token.'; return }
    if ($activation.Action -eq 'open') { Show-RenameToast -IsPreview:([bool]$record.Preview); return }
    $state = Get-ToastNameState
    if (-not (Test-RestartAuthorization -Record $record -NameState $state -Token $activation.Token)) {
        Write-ToastLog 'Restart ignored: preview, expired/used token, changed name, or rename no longer pending.'
        Remove-RenameToast
        return
    }
    $record.Consumed = $true
    Save-ToastRecord $record
    Write-ToastLog 'User selected Restart now. Requesting restart without force-closing applications.'
    # /t greater than zero implies /f. Use /t 0 and DO NOT add /f.
    $process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\shutdown.exe') -ArgumentList @('/r','/t','0') -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        $record.Consumed = $false
        Save-ToastRecord $record
        throw "Restart request failed with exit code $($process.ExitCode). Use Start > Power > Restart."
    }
}

function Remove-ToastRegistration {
    Remove-RenameToast
    foreach ($path in @($script:UserRoot, ('HKCU:\Software\Classes\' + $script:Protocol), ('HKCU:\Software\Classes\AppUserModelId\' + $script:AppId))) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
    $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'IT Device Restart.lnk'
    if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
    Write-ToastLog 'Removed user notification registration.'
}

# MAIN: User-session entry point. Never run this script as SYSTEM.
$mutex = $null
$owned = $false
try {
    if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell 5.1, not PowerShell 7.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -eq 'S-1-5-18' -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) { throw 'An interactive user session is required.' }
    if (($ExpectedSid -and $ExpectedSid -ne $sid) -or
        ($ExpectedSessionId -and $ExpectedSessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId)) {
        throw 'The scheduled reminder reached a different user or session.'
    }
    Write-ToastLog "Started session=$([Diagnostics.Process]::GetCurrentProcess().SessionId) preview=$([bool]$Preview)."
    $script:ToastStage = 'acquire reminder mutex'
    $mutex = [Threading.Mutex]::new($false, ('Local\DeviceRenameToast-' + $sid))
    try { $owned = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { throw 'Another reminder action is still running.' }
    $script:ToastStage = $Mode
    switch ($Mode) {
        'Show' { Show-RenameToast -IsPreview:$Preview }
        'Activate' { Invoke-ToastActivation -Uri $ActivationUri }
        'Cleanup' { Remove-ToastRegistration }
    }
    exit 0
} catch {
    $failure = $_
    $where = $failure.InvocationInfo
    Write-ToastLog ("FAILED stage=[{0}] file=[{1}] line={2} errorId=[{3}] message=[{4}] stack=[{5}]" -f
        $script:ToastStage, $where.ScriptName, $where.ScriptLineNumber, $failure.FullyQualifiedErrorId,
        $failure.Exception.Message, ($failure.ScriptStackTrace -replace '[\r\n]+', ' | '))
    exit 1
} finally {
    if ($owned) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
