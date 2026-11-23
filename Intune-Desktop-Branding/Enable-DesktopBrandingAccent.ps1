#requires -Version 5.1
# Run in the signed-in user's Windows PowerShell session, not as SYSTEM.
$ErrorActionPreference = 'Stop'
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    throw 'Run this script as the signed-in user.'
}
function Write-UserLog($msg) { Write-Host $msg }
    # 3. Apply the activation preferences LAST, after the theme has been opened.
    # These are editable HKCU preferences, not policy settings.
    $personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if (-not (Test-Path -LiteralPath $personalizeKey)) { New-Item -Path $personalizeKey -Force | Out-Null }
    New-ItemProperty -Path $personalizeKey -Name 'SystemUsesLightTheme' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $personalizeKey -Name 'ColorPrevalence' -Value 1 -PropertyType DWord -Force | Out-Null
    # AppsUseLightTheme and the chosen accent RGB are left to the supplied theme.

    if (-not ('DesktopBrandingRefresh' -as [type])) {
    Add-Type -TypeDefinition '
using System;
using System.Runtime.InteropServices;
public static class DesktopBrandingRefresh {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr SendMessageTimeoutW(
        IntPtr hWnd, uint message, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
    public static void Notify() {
        UIntPtr result;
        SendMessageTimeoutW(new IntPtr(0xffff), 0x001A, UIntPtr.Zero,
            "ImmersiveColorSet", 0x0002, 200, out result);
    }
}
'
    }
    [DesktopBrandingRefresh]::Notify()
    Start-Sleep -Seconds 2
    $actual = Get-ItemProperty -LiteralPath $personalizeKey -ErrorAction Stop
    Write-UserLog "Accent toggle readback: SystemUsesLightTheme=$($actual.SystemUsesLightTheme); ColorPrevalence=$($actual.ColorPrevalence)"
    if ($actual.SystemUsesLightTheme -ne 0 -or $actual.ColorPrevalence -ne 1) {
        throw 'Windows did not retain the Start/taskbar accent preferences.'
    }
    Write-UserLog 'Start/taskbar accent preferences saved and refresh requested. Visual rendering must be checked in the user session.'
