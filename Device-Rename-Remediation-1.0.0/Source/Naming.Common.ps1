#requires -Version 5.1
# Shared implementation for the installer. Intune upload scripts contain their
# own embedded copy, because Intune runs them outside this package directory.
# If changing these settings, also update both scripts in the Intune folder.
$script:StateRoot = 'HKLM:\SOFTWARE\DeviceRenameRemediation'
$script:AllowedDeviceTypes = @('LT', 'DT', 'VM', 'SRV', 'PC')
$script:ReminderHours = 4
$script:PopupTimeoutSeconds = 300
$script:PopupTitle = 'Please restart your PC'
$script:PopupMessage = 'Your PC has a pending computer name change. Please save your work and restart your PC to finish applying it. Select Start > Power > Restart. Clicking OK closes this message; it does not restart your PC.'

function Write-NamingLog {
    param([string]$Message)
    # Never write log text to STDOUT: Intune parses that stream.
    try {
        $directory = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
        if (Test-Path -LiteralPath $directory) {
            $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $script:Component, $Message
            Add-Content -LiteralPath (Join-Path $directory 'DeviceRenameRemediation.log') -Value $line -Encoding UTF8 -ErrorAction Stop
        }
    } catch { }
}

function Get-ComputerNameState {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
    $active = [string](Get-ItemPropertyValue -LiteralPath "$root\ActiveComputerName" -Name ComputerName -ErrorAction Stop)
    $configured = [string](Get-ItemPropertyValue -LiteralPath "$root\ComputerName" -Name ComputerName -ErrorAction Stop)
    if ([string]::IsNullOrWhiteSpace($active) -or [string]::IsNullOrWhiteSpace($configured)) {
        throw 'Unable to read both computer-name registry values. Rename is blocked.'
    }
    [pscustomobject]@{
        ActiveName = $active
        ConfiguredName = $configured
        PendingRename = -not [string]::Equals($active, $configured, [StringComparison]::OrdinalIgnoreCase)
    }
}

function Test-NamingConvention {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 15) { return $false }
    $types = ($script:AllowedDeviceTypes | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # First initial + at least one surname character; optional TWO-character suffix.
    # Case-insensitive, whole-string match. Total length is checked separately.
    $pattern = '\A[A-Z][A-Z0-9]{1,8}-(?:' + $types + ')(?:-[A-Z0-9]{2})?\z'
    return ($Name -imatch $pattern)
}

function ConvertTo-NameToken {
    param([Parameter(Mandatory)][string]$Text)
    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return ($builder.ToString().ToUpperInvariant() -replace '[^A-Z0-9]', '')
}

function Get-UserNamePrefix {
    param([AllowNull()][string]$Account)
    if ([string]::IsNullOrWhiteSpace($Account)) { throw 'No console user is signed in.' }
    $leaf = ($Account -split '\\')[-1]
    $leaf = ($leaf -split '@', 2)[0]
    $parts = @($leaf -split '\.')
    # Do not guess a surname from first.middle.last or a display-name account.
    if ($parts.Count -ne 2 -or $parts[0] -notmatch "\A[\p{L}\p{M}'-]+\z" -or $parts[1] -notmatch "\A[\p{L}\p{M}0-9'-]+\z") {
        throw 'The console account must use first.last or first.last@domain. Configure another authoritative name source for other formats.'
    }
    $first = ConvertTo-NameToken -Text $parts[0]
    $last = ConvertTo-NameToken -Text $parts[1]
    if ($first -notmatch '\A[A-Z]' -or $last -notmatch '\A[A-Z]') {
        throw 'Cannot build an ASCII first initial and surname from this account.'
    }
    return ($first.Substring(0, 1) + $last)
}

function Get-ComputerChassisType {
    param([Parameter(Mandatory)]$ComputerSystem)
    if ($ComputerSystem.Model -match 'Virtual|VMware|KVM|VirtualBox|Hyper-V' -or
        $ComputerSystem.Manufacturer -match 'VMware|QEMU|Xen') { return 'VM' }
    # Role 2 is a standalone server, which the original -ge 3 check missed.
    if ([int]$ComputerSystem.DomainRole -ge 2) { return 'SRV' }
    $types = @(Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop | ForEach-Object { $_.ChassisTypes })
    # Evaluate the complete array before returning. 12/18/21 are NOT laptop types.
    if (@($types | Where-Object { $_ -in 8, 9, 10, 11, 14, 30, 31, 32 }).Count -gt 0) { return 'LT' }
    if (@($types | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 35, 36 }).Count -gt 0) { return 'DT' }
    return 'PC'
}

function New-CompliantComputerName {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][ValidateSet('LT','DT','VM','SRV','PC')][string]$DeviceType,
        [switch]$NoRandomSuffix
    )
    $tail = '-' + $DeviceType.ToUpperInvariant()
    if (-not $NoRandomSuffix) {
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        $randomPart = -join (1..2 | ForEach-Object { $alphabet[(Get-Random -Minimum 0 -Maximum $alphabet.Length)] })
        $tail += '-' + $randomPart
    }
    # Nine is the business cap; a three-character SRV token can require eight.
    $maximumPrefix = [Math]::Min(9, (15 - $tail.Length))
    if ($Prefix.Length -lt 2 -or $Prefix -notmatch '\A[A-Z][A-Z0-9]+\z') { throw 'Invalid user-name prefix.' }
    $prefixLength = [Math]::Min($Prefix.Length, $maximumPrefix)
    $name = $Prefix.Substring(0, $prefixLength).ToUpperInvariant() + $tail
    if (-not (Test-NamingConvention -Name $name)) { throw "Generated name '$name' failed validation." }
    return $name
}

function Initialize-SessionMessaging {
    if ('DeviceNaming.SessionMessaging' -as [type]) { return }
    # WTS sends a native dialog into each active user's session from SYSTEM.
    # No ServiceUI, interactive SYSTEM desktop, toast registration, or credentials.
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace DeviceNaming {
    public class UserSession {
        public int Id;
        public string Account;
    }
    public static class SessionMessaging {
        [StructLayout(LayoutKind.Sequential)]
        private struct SessionInfo {
            public int SessionId;
            public IntPtr StationName;
            public int State;
        }
        [DllImport("wtsapi32.dll", EntryPoint="WTSEnumerateSessionsW", ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Enumerate(IntPtr server, int reserved, int version, out IntPtr sessions, out int count);
        [DllImport("wtsapi32.dll", EntryPoint="WTSQuerySessionInformationW", ExactSpelling=true, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Query(IntPtr server, int id, int infoClass, out IntPtr data, out int bytes);
        [DllImport("wtsapi32.dll", EntryPoint="WTSFreeMemory", ExactSpelling=true)]
        private static extern void Free(IntPtr data);
        [DllImport("wtsapi32.dll", EntryPoint="WTSSendMessageW", ExactSpelling=true, CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Send(IntPtr server, int id, string title, int titleBytes,
            string text, int textBytes, int style, int timeout, out int response,
            [MarshalAs(UnmanagedType.Bool)] bool wait);
        private static string QueryText(int id, int infoClass) {
            IntPtr data = IntPtr.Zero;
            int bytes;
            try {
                if (!Query(IntPtr.Zero, id, infoClass, out data, out bytes))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return data == IntPtr.Zero ? "" : Marshal.PtrToStringUni(data);
            } finally { if (data != IntPtr.Zero) Free(data); }
        }
        public static UserSession[] ActiveUsers() {
            IntPtr data = IntPtr.Zero;
            int count;
            var result = new List<UserSession>();
            try {
                if (!Enumerate(IntPtr.Zero, 0, 1, out data, out count))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                int size = Marshal.SizeOf(typeof(SessionInfo));
                for (int index = 0; index < count; index++) {
                    var info = (SessionInfo)Marshal.PtrToStructure(IntPtr.Add(data, index * size), typeof(SessionInfo));
                    if (info.State != 0 || info.SessionId == 0) continue;
                    // Sessions can disappear between enumeration and query.
                    try {
                        string user = QueryText(info.SessionId, 5);
                        if (String.IsNullOrWhiteSpace(user)) continue;
                        string domain = QueryText(info.SessionId, 7);
                        result.Add(new UserSession { Id=info.SessionId, Account=domain + "\\" + user });
                    } catch (Win32Exception) { }
                }
            } finally { if (data != IntPtr.Zero) Free(data); }
            return result.ToArray();
        }
        public static void Notify(int id, string title, string message, int timeout) {
            int response;
            // OK + information icon; asynchronous so Intune never waits on a click.
            if (!Send(IntPtr.Zero, id, title, title.Length * 2, message, message.Length * 2,
                      0x40, timeout, out response, false))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@ | Out-Null
}

function Show-PendingRenameReminder {
    param([Parameter(Mandatory)]$NameState)
    if (-not $NameState.PendingRename) { return }
    # A popup failure must NEVER turn a pending rename into permission to rename.
    try {
        Initialize-SessionMessaging
        $sessions = @([DeviceNaming.SessionMessaging]::ActiveUsers())
        if ($sessions.Count -eq 0) { Write-NamingLog 'Pending rename; no active user session to notify.'; return }
        $key = Join-Path $script:StateRoot 'Notifications'
        if (-not (Test-Path -LiteralPath $script:StateRoot)) { [void](New-Item -Path $script:StateRoot -ErrorAction Stop) }
        if (-not (Test-Path -LiteralPath $key)) { [void](New-Item -Path $key -ErrorAction Stop) }
        foreach ($session in $sessions) {
            try {
                $valueName = 'Session' + $session.Id
                $previous = $null
                $encoded = Get-ItemPropertyValue -LiteralPath $key -Name $valueName -ErrorAction SilentlyContinue
                if ($encoded) {
                    try { $previous = $encoded | ConvertFrom-Json -ErrorAction Stop } catch { $previous = $null }
                }
                $now = [DateTime]::UtcNow
                if ($null -ne $previous -and $previous.Account -eq $session.Account -and
                    $previous.Target -eq $NameState.ConfiguredName -and $previous.Active -eq $NameState.ActiveName) {
                    # Store UTC ticks as a string: ConvertFrom-Json differs across
                    # PowerShell versions in how it converts ISO dates/time zones.
                    $lastTicks = [long]0
                    if ([long]::TryParse([string]$previous.UtcTicks, [ref]$lastTicks)) {
                        $age = ($now.Ticks - $lastTicks) / [double][TimeSpan]::TicksPerHour
                        if ($age -ge 0 -and $age -lt $script:ReminderHours) { continue }
                    }
                }
                [DeviceNaming.SessionMessaging]::Notify($session.Id, $script:PopupTitle, $script:PopupMessage, $script:PopupTimeoutSeconds)
                $record = @{ Account=$session.Account; Target=$NameState.ConfiguredName; Active=$NameState.ActiveName; Utc=$now.ToString('o'); UtcTicks=$now.Ticks.ToString([Globalization.CultureInfo]::InvariantCulture) } | ConvertTo-Json -Compress
                [void](New-ItemProperty -LiteralPath $key -Name $valueName -Value $record -PropertyType String -Force -ErrorAction Stop)
                Write-NamingLog "Reboot reminder sent to session $($session.Id)."
            } catch { Write-NamingLog "Could not send/store a reminder for session $($session.Id): $($_.Exception.Message)" }
        }
    } catch { Write-NamingLog "Reboot reminder unavailable: $($_.Exception.Message)" }
}

function Get-RenameEligibility {
    param([Parameter(Mandatory)]$NameState)
    if ($NameState.PendingRename) {
        return [pscustomobject]@{ Eligible=$false; Reason='A computer rename is already pending.'; Prefix=$null; System=$null }
    }
    if (Test-NamingConvention -Name $NameState.ActiveName) {
        return [pscustomobject]@{ Eligible=$false; Reason='Current name already matches the naming convention.'; Prefix=$null; System=$null }
    }
    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($system.PartOfDomain) {
        return [pscustomobject]@{ Eligible=$false; Reason='AD domain-joined computer excluded; this package does not supply domain credentials.'; Prefix=$null; System=$system }
    }
    try { $prefix = Get-UserNamePrefix -Account $system.UserName }
    catch { return [pscustomobject]@{ Eligible=$false; Reason=$_.Exception.Message; Prefix=$null; System=$system } }
    return [pscustomobject]@{ Eligible=$true; Reason='Rename required and console account is usable.'; Prefix=$prefix; System=$system }
}

function Save-RenameReceipt {
    param([Parameter(Mandatory)][string]$TargetName)
    # A single JSON value avoids partially committed detection properties.
    $record = @{ Schema=1; TargetName=$TargetName; AppliedUtc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress
    if (-not (Test-Path -LiteralPath $script:StateRoot)) { [void](New-Item -Path $script:StateRoot -ErrorAction Stop) }
    [void](New-ItemProperty -LiteralPath $script:StateRoot -Name Receipt -Value $record -PropertyType String -Force -ErrorAction Stop)
}
