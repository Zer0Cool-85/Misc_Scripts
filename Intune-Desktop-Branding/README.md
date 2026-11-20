# DesktopBranding — ThemeApply-1

This revision addresses an existing desktop retaining its wallpaper and selected
accent after installation. The working session-targeted task launcher is retained.
Runtime filenames, task names and registry namespace remain DesktopBranding.

## Package and install

Place exactly one custom .theme in Theme, the desktop image in Wallpaper, and the
lock-screen image in Lockscreen. No theme or image assets are included in this ZIP.
Default image names are Company.jpg and CompanyLock.jpg. Reuse your own assets.
The theme must include [Control Panel\Desktop] and [VisualStyles], with an explicit
ColorizationColor=0xAARRGGBB in [VisualStyles]. Example: 0xC43F177E selects #3F177E.
Missing/invalid colors now fail instead of silently substituting a default color.

Run as SYSTEM through an Intune Win32 app (Install behavior: System):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -CompanyFolder "ModMed" -WallpaperImg "ModMed.jpg" -LockscreenImg "ModMedLock.jpg"
```

For Intune's 32-bit Win32 command host, use native Windows PowerShell:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -CompanyFolder "ModMed" -WallpaperImg "ModMed.jpg" -LockscreenImg "ModMedLock.jpg"
```

Keep your existing parameter values when rebuilding. CompanyFolder (alias Location),
WallpaperImg and LockscreenImg are supported. ThemeFile and PreserveThemeSettings
are not parameters in this original baseline: place your chosen theme in Theme.
Its original filename is preserved. Install/uninstall scripts must be packaged
alongside the asset folders using IntuneWinAppUtil.exe.

Detection: 64-bit registry, HKLM\SOFTWARE\Company\DesktopBranding, string value
Revision equals ThemeApply-1. Version DWORD=1 remains for compatibility. Company
in this registry key is fixed independently of the CompanyFolder parameter.
Update detection when replacing the earlier package so its marker cannot satisfy
this revision's detection. Successful staging with no desktop still counts as
installed; it does not prove any future user's visual settings were applied.

## Application behavior

1. Copy assets to Windows\Web\Wallpaper\<CompanyFolder> and the supplied theme to
   Windows\Resources\OEM Themes. Required source images are checked first.
2. Prepare the deployed theme copy: point Wallpaper to the staged image, disable
   automatic accent selection, and set SystemMode=Dark. Remove any [Slideshow]
   section because this deployment specifies a single desktop picture. Retain
   the theme filename, display name, and other sections. The package source file
   is untouched. WallpaperStyle and TileWallpaper are read from your theme, with
   defaults of Fill (10) and non-tiled (0) when missing/invalid.
3. Run the original Default User hive seeding.
4. In the existing desktop session, request activation of the deployed theme and
   check CurrentTheme for up to 15 seconds. Log whether that exact source path is
   selected. Opening a file alone is no longer reported as proof of application.
5. Apply the lock screen with the existing WinRT code, then explicitly set the
   staged desktop picture through SystemParametersInfoW. Write the supplied
   theme's accent color/palette to the user's Explorer and DWM preferences,
   disable automatic color selection, enable dark Windows mode, and turn on the
   Start/taskbar accent preference. Broadcast a color-settings change.
6. Check wallpaper, selected accent/palette and toggle registry readbacks. Fail
   the user task if these differ from the requested values. The parent checks
   the task result before writing its successful-install revision marker.

The taskbar uses a darker shade derived from the selected accent, as in the
original palette generator; it need not visually match the base RGB exactly.
There are no private uxtheme ordinal calls, Explorer restarts, forced sign-outs,
or forced Settings termination in the install helper. Opening a theme may show
Windows Settings.

Windows may retain a Custom/unsaved theme label after individual settings change.
If CurrentTheme does not match the source path, the log explicitly warns that
other theme components (such as sounds and icons) are unverified. This revision
explicitly applies the requested wallpaper and accent even in that case; it does
not claim guaranteed activation of every component or a particular Settings tile.
App light/dark mode remains controlled by actual theme activation, not forced by
the final user helper. Registry readback verifies saved settings, not visible pixels.
Accent registry values are Windows implementation details and need a build-specific
pilot; the wallpaper setter uses a documented public Windows API.

Users can change these preferences afterward. There is no recurring enforcement,
policy lock, or per-user marker. Explicit reinstall reapplies the supplied defaults.
The standalone Enable-DesktopBrandingAccent.ps1 remains a toggle-only diagnostic;
it does NOT deploy this theme, wallpaper, or selected RGB. Use the installer for
this fix.

## Session launcher and deployment scope

Install and uninstall discover the sole nonzero Explorer session number, register
a limited task for the built-in local Users group, and call
RunEx(null, 4, sessionId, null). No Entra user-name/SID lookup or password is used.
Generated helpers verify the session and reject service-account execution.
Multiple Explorer sessions cause a clear failure instead of choosing arbitrarily.
Task completion and exit status are checked, with a three-minute limit.

With no Explorer desktop (including Autopilot before a user desktop), the current-user
step is skipped and the original Default User hive setup is used. This focused
revision does not add a first-logon lock-screen hook or certify future-profile
visual application. Native reg.exe error handling in Default User setup and the
original uninstall assumptions have not been redesigned. Earlier experimental
persistent logon tasks must not compete with this original baseline.

## Uninstall and logs

Uninstall is unchanged from the working SessionFix package. Use the same folder:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1 -CompanyFolder "ModMed"
```

ThemeName can identify the specific .theme for uninstall; retain the source Theme
folder with the package. Review the original uninstall behavior before production
use; it resets branding rather than restoring a captured backup of preferences.

Logs:

- Install: %ProgramData%\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log
- User: %ProgramData%\Apply-UserTheme.log (merged/deleted after success if available)
- Uninstall: %ProgramData%\Microsoft\IntuneManagementExtension\Logs\App-Uninstall-DesktopBranding.log

Task names remain ApplyOrgThemeTemp and RevertOrgThemeTemp. Task/helper are retained
on timeout or user-task failure for inspection. User log creation is best effort
under the original log permissions; task exit status is checked separately.

## Pilot and validation

On a test device, choose a visibly different wallpaper and accent first. Install
this revision through Intune and check that the new picture appears, the specified
accent is selected, and the Start/taskbar toggle is enabled. Confirm the log's
wallpaper/color readback and theme-selection result. Then change those preferences
manually and sign out/in to confirm they remain editable. A sign-out/in may be
needed for some shell surfaces to repaint; the installer does not force one.

PowerShell syntax, generated helpers, embedded C# compilation, mocked session
launch/error cases, theme preparation and RGB conversions were checked with
PowerShell 7.4.6 on Linux. Windows PowerShell 5.1, actual Windows shell rendering,
Task Scheduler, Intune and Autopilot could not be exercised here. See VALIDATION.txt.
Install-theme-apply-changes.diff records this revision; older diffs are historical.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow
- https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview
- https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nf-taskschd-iregisteredtask-runex
