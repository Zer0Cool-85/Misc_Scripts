# DesktopBranding — ThemeApply-2

This revision addresses an existing desktop retaining its wallpaper and selected
accent after installation. The working session-targeted task launcher is retained.
Runtime filenames, task names and registry namespace remain DesktopBranding.

## Package and install

Place exactly one custom .theme in Theme, the desktop image in Wallpaper, and the
lock-screen image in Lockscreen. No theme or image assets are included in this ZIP.
Default image names are Company.jpg and CompanyLock.jpg. Reuse your own assets.
The theme must include [Control Panel\Desktop] and [VisualStyles], with an explicit
ColorizationColor=0xAARRGGBB in [VisualStyles]. Example: 0xC43F177E selects #3F177E.
Without an override, a missing or invalid theme color fails validation. Supply -AccentColor "#3F177E" to set the deployed theme, profile defaults and signed-in desktop to a specific RGB.

Run as SYSTEM through an Intune Win32 app (Install behavior: System):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -CompanyFolder "Company" -WallpaperImg "Company.jpg" -LockscreenImg "CompanyLock.jpg"
```

For Intune's 32-bit Win32 command host, use native Windows PowerShell:

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -CompanyFolder "Company" -WallpaperImg "Company.jpg" -LockscreenImg "CompanyLock.jpg"
```

For the Company purple, append `-AccentColor "#3F177E"` to the install command. Omit it to read the RGB from the supplied theme. The script logs the selected RGB before switching sessions. Keep your existing image and folder arguments when rebuilding. CompanyFolder (alias Location),
WallpaperImg and LockscreenImg are supported. ThemeFile and PreserveThemeSettings
are not parameters in this original baseline: place your chosen theme in Theme.
Its original filename is preserved. Install/uninstall scripts must be packaged
alongside the asset folders using IntuneWinAppUtil.exe.

Detection: 64-bit registry, HKLM\SOFTWARE\Company\DesktopBranding, string value
Revision equals ThemeApply-2. Version DWORD=1 remains for compatibility. Company
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
5. Set the wallpaper, save the Explorer and DWM colors, and enable the Start/taskbar accent. Existing registry keys are opened in place.
6. Read the system accent through UISettings.GetColorValue(Accent). Require two consecutive samples matching the requested RGB and saved preferences. If the shell still reports another color, reapply the accent once and log both RGBs. Verify the wallpaper and apply the lock screen.
7. Copy the per-attempt user messages into the main Intune log before evaluating the task result. A failed step reports its name, script line and exception. The device revision is recorded after a successful user task on an active desktop.

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
visual application. The original Company Portal installer still handles Default User setup. The repaired uninstaller checks hive load and unload and scopes the reset to the installed theme. Earlier experimental
persistent logon tasks must not compete with this original baseline.

## Company Portal uninstall and logs

Package both scripts with the original asset folders. Use the installed CompanyFolder for removal.

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1 -CompanyFolder "Company"
```

The uninstaller derives file ownership from the packaged Theme, Wallpaper and
Lockscreen folders using the script's own directory. For a manual retry without
those folders, pass -ThemeName, -WallpaperImg and -LockscreenImg explicitly.
Supply -CompanyFolder if it was customized, especially after a partial removal.

The user reset runs first, from a protected, user-readable folder under Program
Files. It checks the wallpaper and theme individually. It opens the stock theme
when both the current source theme and wallpaper match, and resets a matching
wallpaper even if Windows labeled the theme Custom. It resets the lock image when
Windows identifies a matching file path or a readable cached file has matching
bytes. When ownership cannot be determined, it leaves the current lock image in
place. Previous personalization choices were never backed up. A custom accent
can remain when a stock theme reset would overwrite user changes.

After the reset, the device script resets the Default User theme pointer only
if it references the deployed file, removes the named assets, and removes the
Company Portal marker last. A failed user reset returns an error and retains
the assets and detection marker for a retry. No desktop present skips the live
reset. Multiple Explorer sessions are reported in the machine log.

- Install log: %ProgramData%\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log
- User install log: the main install log includes the most recent helper messages. Look for `Accent pass` and `ERROR [step]`. On failure, the run-specific DesktopBranding-*.log is retained in the OEM Themes folder. Older packages used %ProgramData%\Apply-UserTheme.log.
- Uninstall log: %ProgramData%\Microsoft\IntuneManagementExtension\Logs\App-Uninstall-DesktopBranding.log
- User reset log: %LOCALAPPDATA%\DesktopBranding\Uninstall.log in the affected profile

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

## Two Intune deployments

**Company Portal.** Assign this Win32 app as Available for enrolled devices to
the intended users and enable available uninstall if desired. Keep its current
64-bit Revision = ThemeApply-2 detection. ESP uses its own files and registry
key, so a successfully staged ESP app still permits one Company Portal repair
install. After the Portal app itself is detected, uninstall/reinstall enables
another manual application.

**Classic Autopilot device ESP.** Download Install-DesktopBrandingAutopilot.ps1
separately. Build the deployment script on your packaging computer with your
actual source assets. The source .theme must have an explicit [VisualStyles]
ColorizationColor and a [Control Panel\Desktop] section. This example uses
the existing Company filenames. Supply actual filenames as needed.

```powershell
.\Install-DesktopBrandingAutopilot.ps1 -Mode Build -ThemeFile .\Theme\Custom.theme -WallpaperFile .\Wallpaper\Company.jpg -LockscreenFile .\Lockscreen\CompanyLock.jpg -OutputScript .\ESP\Install-DesktopBrandingAutopilot.ps1
```

Create a second .intunewin with only the generated script in its source folder.
For example, from a workstation with Microsoft's content prep tool:

```text
IntuneWinAppUtil.exe -c .\ESP -s Install-DesktopBrandingAutopilot.ps1 -o .\Output
```

| ESP app setting | Value |
| --- | --- |
| Install behavior | System |
| Install command | `%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBrandingAutopilot.ps1 -Mode Stage` |
| Uninstall command | Same command with `-Mode Unstage` |
| Detection | 64-bit registry, `HKLM\SOFTWARE\Company\DesktopBrandingAutopilot`, string `Revision` equals `ESP-1` |
| Assignment | Required to the Autopilot **device** enrollment group. Select the app in the device ESP blocking app list. Keep migrated devices outside the assignment. |

OOBEComplete guards the staging path. It reports whether Windows Welcome has
completed. Assignment to the Autopilot device group and ESP blocking-app
selection control deployment timing. A late install on an already provisioned
device with no ESP marker returns an error and logs why. If your Required group
also contains already-enrolled devices, scope it to incoming deployments or add
an OOBE-only Win32 requirement to avoid late installation attempts.

During device ESP, the script stages the theme and both images under
%ProgramFiles%\DesktopBranding\Autopilot. In the Default User hive it writes the
wallpaper, the prepared theme path and an HKCU RunOnce entry. Each profile created
after staging inherits the entry. Windows launches it at first desktop sign-in,
where it applies the theme, wallpaper, fixed accent and per-user lock image.
It does not set the pre-sign-in/OOBE lock screen. The installed ESP marker
records device staging. Successful first-desktop application writes a separate
HKCU marker of the same name. A failed first desktop attempt is logged and the
Company Portal app can repair it. Existing profiles do not inherit Default User
changes. No recurring job enforces personalization.

The ESP device log is %ProgramData%\Microsoft\IntuneManagementExtension\Logs\DesktopBranding-Autopilot.log.
The first-desktop log is %LOCALAPPDATA%\DesktopBranding\Autopilot.log.
Unstage removes the template handoff, its matching default pointers and the
device marker. It retains assets used by existing profiles. Pending handoffs
check the device marker before applying anything.

Pilot on one fresh Autopilot device and one migrated device. On the fresh device,
verify that ESP finishes, lock the screen after the first desktop, then change
the wallpaper and sign in again. The user's choice should persist. On the
migrated device, install from Company Portal, uninstall, and confirm the Portal
marker is gone. If uninstall fails, compare the machine and user reset logs.

Microsoft documentation:
- https://learn.microsoft.com/en-us/troubleshoot/mem/intune/device-enrollment/understand-troubleshoot-esp
- https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys
- https://learn.microsoft.com/en-us/windows/win32/api/oobenotification/nf-oobenotification-oobecomplete
