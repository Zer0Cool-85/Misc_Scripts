# Desktop Branding 2.1.0

Win32 app source package for ModMed. Applies a custom theme, desktop wallpaper,
custom accent color on Start/taskbar, and a per-user lock-screen image as editable
defaults. Defaults are applied once per user; subsequent successful runs exit
without resetting the user's choices.

**Add your images before packaging. This ZIP does not include your branding
images and is not an `.intunewin` file.**

## Package contents

| File | Purpose |
| --- | --- |
| `Install-DesktopBranding.ps1` | SYSTEM installer, payload staging, and task registration |
| `Apply-DesktopBranding.ps1` | Interactive user initialization and per-component completion tracking |
| `Uninstall-DesktopBranding.ps1` | Removes the V2 deployment mechanism while preserving user appearance |
| `Detect-DesktopBranding.ps1` | Intune detection of installed files and the logon task |
| `DesktopBranding.Theme.ps1` | Shared parsing and custom-theme handling; keep beside the other scripts |
| `Theme` | Your optional custom `.theme` and dependencies; includes an optional example |
| `Tests/Test-CustomTheme.ps1` | Theme-transformation regression tests and native PowerShell parser checks |
| `Wallpaper/ADD-YOUR-WALLPAPER.txt` | Instructions for the missing desktop image |
| `Lockscreen/ADD-YOUR-LOCKSCREEN.txt` | Instructions for the missing lock-screen image |
| `VALIDATION.txt` | Checks performed while preparing this archive and their limits |

Version 2.1.0 adds optional custom `.theme` support while keeping generated
themes as the default. The shared helper is required in the Win32 source folder.
The pure theme transformations and PowerShell syntax were tested with PowerShell
7.4.6 on Linux. Windows desktop/WinRT/Task Scheduler behavior and Windows
PowerShell 5.1 still require a Windows pilot; see `VALIDATION.txt`.

## 1. Add your images

Extract the ZIP to a local folder, for example:

```text
C:\Intune\Desktop-Branding-2.1.0
```

For generated themes and the default custom-theme mode, add these real images:

| Destination inside the extracted package | Required default filename |
| --- | --- |
| `Wallpaper` | `ModMed.jpg` |
| `Lockscreen` | `ModMedLock.jpg` |

The `.txt` files are instructions, not image placeholders to rename. They can be
deleted after adding your images. In `-PreserveThemeSettings` mode, the separate
`Wallpaper` image is not required: the theme supplies its own wallpaper or
slideshow. The `Lockscreen` image is still required in every mode.

Without `-ThemeFile`, the helper generates a named ModMed theme as before.
With `-ThemeFile`, it deploys the exact file you name from the package
`Theme` folder. See the custom-theme examples below.

## 2. Customize the installation

The default accent is purple, `#3F177E`. Use a six-digit RGB value, optionally
prefixed by `#`. For example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -AccentHex "#3F177E"
```

| Parameter | Default | Notes |
| --- | --- | --- |
| `CompanyFolder` | `ModMed` | Also determines task names, registry paths, per-user folder, and theme display name |
| `AccentHex` | `#3F177E` for generated themes | Explicit value overrides custom-theme color; otherwise read from the custom theme |
| `WallpaperImg` | `ModMed.jpg` | Filename within `Wallpaper`; JPG/JPEG/PNG/BMP |
| `LockscreenImg` | `ModMedLock.jpg` | Filename within `Lockscreen`; JPG/JPEG/PNG |
| `DefaultsId` | `Defaults-v2` | Identity of this one-time set of user defaults |
| `ThemeFile` | Not set | Exact `.theme` filename inside the package `Theme` folder |
| `PreserveThemeSettings` | Off | Use the custom theme visual settings without package wallpaper/accent overrides |

Example using different image filenames:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -AccentHex "#3F177E" -WallpaperImg "Desktop2026.png" -LockscreenImg "Lock2026.png"
```

**Keep `DefaultsId` unchanged for ordinary reinstalls and updates.** Changing the
color or payload does not reset users who have already completed the relevant
steps. Their image copies and completion markers are retained. To deliberately
apply an entirely new set of defaults to everyone, specify a new `DefaultsId`,
for example `Defaults-v3`; that intentionally resets the requested appearance
once for each user.

If you customize `CompanyFolder`, pass the same value to uninstall and update
the two `ModMed` references in the detection script. Do not change only the
installation folder while leaving detection aimed at the default paths.

## Custom .theme files

Put your file at `Theme/Custom.theme` in the extracted source folder. The file
must include the normal `[Control Panel\Desktop]`, `[VisualStyles]`, and
`[MasterThemeSelector]` sections, with `MTSM=DABJDKT`. `.themepack` and
`.deskthemepack` containers are not supported as direct inputs; extract them first.

### Use your theme with the branding wallpaper and accent handling

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -ThemeFile "Custom.theme"
```

This mode uses your theme as the base. It:

- Preserves the theme name, cursor/icon/sound settings, app mode, transparency,
  and other unrelated settings.
- Replaces the wallpaper path in the per-user theme copy with the packaged
  `Wallpaper` image, retaining its WallpaperStyle and TileWallpaper settings.
  Missing placement values default to Fill / not tiled.
- Removes `[Slideshow]` because this mode supplies one package-managed picture.
- Reads RGB and alpha from `[VisualStyles] ColorizationColor=0xAARRGGBB` when
  you omit `-AccentHex`. A missing/invalid fixed color requires an explicit
  `-AccentHex` or the preserve option; it does not silently use a different color.
- Applies the complete accent palette and Start/taskbar accent toggle. Windows
  shell mode becomes Dark, and automatic accent selection is disabled once.
- Leaves an omitted AppMode alone; an explicit Light/Dark AppMode is retained.
- Sets the separately supplied lock-screen image once.

For an explicit accent override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -ThemeFile "Custom.theme" -AccentHex "#3F177E"
```

An explicit `-AccentHex` wins over the theme RGB. A valid alpha byte in the source
ColorizationColor is retained; otherwise the package uses `C4`. Avoid copying
`-AccentHex "#3F177E"` into your custom-theme command if you want the theme's own
accent color instead.

### Preserve the theme's visual settings

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -ThemeFile "Custom.theme" -PreserveThemeSettings
```

This keeps the theme's wallpaper/slideshow, color selection, system/app modes,
placement and other visual settings. It skips package wallpaper and accent
registry overrides, including the Start/taskbar accent switch. If the theme uses
Light Windows mode, the package leaves it Light. Use the default custom-theme
mode when you want the package to ensure the dark shell and Start/taskbar accent.

The separate lock-screen image is still applied, and its picture-mode preferences
are still initialized. This option preserves the supplied theme's *visual*
settings; it does not suppress the separate lock-screen step. It is not a
byte-for-byte deployment: the per-user copy is saved as UTF-16, and the optional
resource token below is substituted.

Do not combine `-PreserveThemeSettings` with an explicit `-AccentHex` or
`-WallpaperImg`; the installer rejects those conflicting inputs. It requires a
`-ThemeFile`. Contrast/classic themes with an empty visual-style Path need this
preserve mode.

### Include theme resources

The entire `Theme` folder is copied to the installed payload and then to each
initialized user's profile. For files under `Theme/Assets`, use the exact
uppercase token `%BRANDINGTHEMEDIR%` in your theme:

```ini
[Theme]
BrandImage=%BRANDINGTHEMEDIR%\Assets\Logo.png

[Control Panel\Desktop]
Wallpaper=%BRANDINGTHEMEDIR%\Assets\YourWallpaper.jpg

[Control Panel\Cursors]
Arrow=%BRANDINGTHEMEDIR%\Assets\Arrow.cur
```

The token expands to the user's copied Theme directory. This makes those
resources independent of the installer cache and keeps them available after
uninstall. The theme source in the package is not edited.

Standard Windows paths such as `%SystemRoot%\...` are left intact. Other relative
paths, network paths and paths under the authoring user's profile are **not**
automatically repaired. Supply the dependencies and fix those references before
packaging. See `Theme/README.md` for details. `Example-ModMed.theme` is an optional
example and is never selected unless you pass its exact filename.

### Existing users who already completed 2.0.0

Updating to 2.1.0 alone preserves their completion markers. To deliberately try
or deploy your custom theme to those users, use a new DefaultsId:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -ThemeFile "Custom.theme" -DefaultsId "Defaults-custom-v1"
```

Add `-PreserveThemeSettings` if that is your intended mode. Changing DefaultsId
reinitializes the requested appearance once per user. Keep that new identifier
unchanged for later repairs/reinstalls so user changes remain respected.

## 3. Create the Intune Win32 package

Use Microsoft's Win32 Content Prep Tool on a Windows workstation. Keep its
output directory outside the source directory to avoid including generated
packages in subsequent builds.

```powershell
.\IntuneWinAppUtil.exe -c "C:\Intune\Desktop-Branding-2.1.0" -s "Install-DesktopBranding.ps1" -o "C:\Intune\Output" -q
```

Microsoft's tool repository:
[Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)

Upload the resulting `.intunewin` as a Windows app (Win32).

## 4. Configure Intune

| Setting | Value |
| --- | --- |
| Install behavior | System |
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -AccentHex "#3F177E"` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1` |
| Device restart behavior | No specific action |
| Architecture | x64 pilot; ARM64 has not been validated |
| Minimum OS | Set to your supported Windows 11 baseline |
| Detection rules | Use a custom detection script: `Detect-DesktopBranding.ps1` |
| Run detection script as 32-bit process on 64-bit clients | No |
| Enforce detection-script signature check | No for these unsigned files; use your signing process if required |

Begin with a small pilot device group. For an existing app, replace the package
content and update the commands and detection rule together. Do not leave the
old `Custom.theme` file-existence rule as the V2 detection rule.

If replacing V1, use the V2 uninstall command for V2. The old wildcard command
shown in the original install script can delete unrelated themes from the shared
OEM Themes directory. V2 only removes its own deployment payload and tasks. It
does not undo old Default User hive edits or clean up V1 OEM images/themes.
Avoid overlapping deployments that continue applying old defaults.

## Autopilot and existing desktops

- During device ESP, the SYSTEM installer stages files and registers the logon
  task. Installation can succeed before a real user signs in.
- The logon task runs approximately 30 seconds after sign-in, in the user's
  context. The helper waits up to 60 more seconds for Explorer.
- If a desktop already exists at installation time, the installer creates and
  starts an on-demand task for each distinct Explorer owner SID.
- `defaultuser0`, service accounts, and session 0 are skipped.
- Task Scheduler can retry a failed run twice, one minute apart; a later sign-in
  also retries unfinished work. Successful component markers prevent replaying
  completed steps.
- The installer reports that the deployment mechanism is staged. It does not
  claim that every profile has finished personalization.

## User experience and limits

Generated mode starts with Dark Windows mode and Light app mode. Custom branding
mode uses a Dark Windows shell and retains the custom app-mode choice. Preserve
mode leaves both modes to the theme. Start/taskbar accent coloring requires the
dark Windows shell. The package uses ordinary preferences, not Personalization
CSP or policy keys that prevent subsequent changes.

The helper activates the generated or supplied `.theme` through Windows. This may open
Personalization once. It does not close Settings, restart Explorer, or reboot.
In generated/custom branding mode, after theme activation it writes the complete
accent palette and corresponding Explorer/DWM DWORDs. Preserve mode skips those
writes. Some shell surfaces may need a sign-out/sign-in to render
the updated preferences. The generated darker shades and transparency can make
the rendered taskbar look darker than the RGB value selected in Settings.

In every mode, the lock screen is set for the signed-in user through WinRT. This does not brand
the screen before anyone has signed in. Spotlight/slideshow preferences are
changed to picture mode once, and remain user-editable afterward. Existing MDM
or Group Policy personalization enforcement takes precedence; this package does
not remove those policies.

Accent registry values are Windows implementation details, not a stable public
management API. Validate the exact Windows builds in your deployment rings. The
script avoids the original undocumented `uxtheme.dll` ordinal calls. For the
default purple, Explorer/DWM AccentColor is `0xFF7E173F` and DWM ColorizationColor
is `0xC43F177E`.

## Logs, state, and troubleshooting

Default locations:

| Item | Location |
| --- | --- |
| Installation log | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBrandingV2.log` |
| Installed payload/configuration | `%ProgramFiles%\ModMed\DesktopBrandingV2` |
| User log | `%LOCALAPPDATA%\ModMed\DesktopBrandingV2\Defaults-v2\Apply-DesktopBranding.log` |
| User images | Same directory as the user log |
| Custom theme resources | `Theme` subfolder under the user log directory |
| Generated theme | `%LOCALAPPDATA%\Microsoft\Windows\Themes\ModMed-Defaults-v2.theme` |
| Machine detection state | `HKLM\SOFTWARE\ModMed\DesktopBrandingV2` |
| Per-user completion state | `HKCU\Software\ModMed\DesktopBrandingV2\Defaults-v2` |
| Logon task | `ModMed-DesktopBrandingV2` |
| On-demand task prefix | `ModMed-DesktopBrandingV2-Now-` |

For an Intune install success with missing branding, inspect the affected user's
log and scheduled-task result. Detection intentionally does not compare the
current wallpaper, accent, or lock screen against the company values.

Run the following as the affected user to inspect completion:

```powershell
Get-ItemProperty 'HKCU:\Software\ModMed\DesktopBrandingV2\Defaults-v2'
Get-Content "$env:LOCALAPPDATA\ModMed\DesktopBrandingV2\Defaults-v2\Apply-DesktopBranding.log" -Tail 80
```

Task status can be inspected from an elevated PowerShell window:

```powershell
Get-ScheduledTask -TaskName 'ModMed-DesktopBrandingV2*' |
    Get-ScheduledTaskInfo |
    Select-Object TaskName, LastRunTime, LastTaskResult
```

The installed helper can also be run manually from a regular Windows PowerShell
window as the affected user. It retries incomplete steps and otherwise exits:

```powershell
& "$env:ProgramFiles\ModMed\DesktopBrandingV2\Apply-DesktopBranding.ps1"
```

Do not run the user helper as SYSTEM to test HKCU settings. Use Windows
PowerShell 5.1, not PowerShell 7, for the WinRT implementation.

## Pilot checks

1. Test on a fresh Windows 11/Autopilot profile and verify all four components
   after the first desktop appears. Check the user log and task result.
2. Test installation on an already signed-in standard user's device. Confirm
   the user task runs and no Explorer restart occurs.
3. Lock the device to verify the per-user lock-screen image.
4. Change wallpaper, accent and lock-screen image manually. Sign out/in, then
   reinstall with the same `DefaultsId`. Verify the user's choices remain.
5. For custom mode, verify your theme name, cursor/sound settings, selected accent
   and wallpaper placement. Test preserve mode separately if you will deploy it.
6. Uninstall V2. Verify tasks/payload are removed and selected user images still
   display. Completion markers, theme files and image copies remain by design.

Run the included pure-helper regression tests in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-CustomTheme.ps1
```

These tests parse all scripts and check theme/color precedence, preservation,
resource-token substitution, section editing and invalid inputs. They do not
install the package or change the desktop.

For a syntax-only check using the native PowerShell parser on Windows (this
does not execute the installation), run from the extracted package folder:

```powershell
$failed = $false
Get-ChildItem -LiteralPath . -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count) {
        $failed = $true
        Write-Host "FAILED: $($_.Name)" -ForegroundColor Red
        $parseErrors | Format-List Message, Extent
    } else {
        Write-Host "PASS: $($_.Name)" -ForegroundColor Green
    }
}
if ($failed) { throw 'One or more PowerShell files contain parser errors.' }
```

## Microsoft references

- [Theme file format](https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview)
- [Windows color modes and accent colors](https://support.microsoft.com/en-us/windows/experience/personalization/personalize-your-colors-in-windows)
- [LockScreen.SetImageFileAsync](https://learn.microsoft.com/en-us/uwp/api/windows.system.userprofile.lockscreen.setimagefileasync)
- [Group logon triggers](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nn-taskschd-ilogontrigger)
- [Personalization CSP and enforcement behavior](https://learn.microsoft.com/en-us/windows/client-management/mdm/personalization-csp)

