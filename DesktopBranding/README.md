# Desktop Branding – Intune Win32 App

Sets a corporate **theme, desktop wallpaper, accent color (shown on Start, the taskbar and title bars) and lock screen image** as the *starting* configuration on Windows 10/11 devices. Nothing is enforced through policy: users can change any of it afterwards in **Settings › Personalization**.

It works in both deployment scenarios:

| Scenario | What happens |
|---|---|
| **Autopilot – device ESP** (no user signed in yet) | The Default User profile is seeded, and each new user gets the full branding once at first sign-in. |
| **Autopilot – account setup ESP** (user signed in, desktop not started yet) | The branding is queued for that user and applies when their desktop starts. |
| **Post-enrollment** (user signed in and working) | The branding applies right away in the user's session. Future users on the device also get it. |

---

## Package contents

```
DesktopBranding\
├── Install-DesktopBranding.ps1     Install (runs as SYSTEM)
├── Uninstall-DesktopBranding.ps1   Uninstall (runs as SYSTEM)
├── Apply-UserBranding.ps1          Per-user apply/revert (launched by the scripts above; runs as the user)
├── Theme\
│   └── CompanyBrand.theme          Starter theme – edit DisplayName (and the accent color if you like)
├── Wallpaper\
│   └── Company.jpg                 ← add your wallpaper
└── Lockscreen\
    └── CompanyLock.jpg             ← add your lock screen image
```

> The `PLACE-…-HERE.txt` files in `Wallpaper\` and `Lockscreen\` are placeholders. Delete them before packaging. Only image files are copied anyway.

---

## 1. Prepare the source folder

1. **Images**: copy your wallpaper into `Wallpaper\` and your lock screen image into `Lockscreen\`.
   The default file names are `Company.jpg` and `CompanyLock.jpg`. If yours differ, pass `-WallpaperImg` / `-LockscreenImg` on the install command line.
2. **Theme**: edit `Theme\CompanyBrand.theme`:
   - Set `DisplayName=`. This is the name users see under **Settings › Personalization › Themes**.
   - Set `ColorizationColor=0XC4RRGGBB` to your accent color. The default is `0XC43F177E` = **#3F177E**. You can also leave it and pass `-AccentColor "#RRGGBB"` instead.
   - You can use your own exported `.theme` instead. Keep only **one** `.theme` in `Theme\`, or name it with `-ThemeFile`.
   - Avoid naming it `Custom.theme`, because Windows uses that name for a user's own unsaved theme.

   You don't need to fix the wallpaper path, `AutoColorization` or the dark/light mode lines by hand. The install script rewrites them in the deployed copy so they match the script's parameters.

---

## 2. (Optional) Test locally before packaging

Use [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec) to run the install as SYSTEM, the same way Intune does, while you're signed in to a test VM:

```cmd
psexec.exe -s -i C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\DesktopBranding\Install-DesktopBranding.ps1
```

Using the 32-bit PowerShell here mimics Intune, and also tests the script's automatic relaunch in 64-bit PowerShell. Check the log (see [Logs](#logs--troubleshooting)), then test `Uninstall-DesktopBranding.ps1` the same way.

---

## 3. Build the .intunewin file

Download the [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool) and run:

```cmd
IntuneWinAppUtil.exe -c C:\Temp\DesktopBranding -s Install-DesktopBranding.ps1 -o C:\Temp\Output -q
```

The output is `C:\Temp\Output\Install-DesktopBranding.intunewin`.

---

## 4. Create the Win32 app in Intune

**Intune admin center › Apps › Windows › + Add › App type: Windows app (Win32)** › select the `.intunewin` file.

### App information
| Field | Value |
|---|---|
| Name | Desktop Branding |
| Publisher | *Your company* |
| Version | 1 |

### Program
| Field | Value |
|---|---|
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-DesktopBranding.ps1` |
| Installation time required (mins) | 15 |
| Allow available uninstall | Yes (optional) |
| Install behavior | **System** |
| Device restart behavior | **No specific action** |
| Return codes | Leave the defaults (`0` = success, `1` = failed) |

Example with custom parameters:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-DesktopBranding.ps1 -AccentColor "#3F177E" -LockscreenImg "Lock2026.jpg" -Version 1
```

If you changed `-CompanyFolder` on install, pass the same value to the uninstall command.

### Requirements
| Field | Value |
|---|---|
| Operating system architecture | x64 (add ARM64 if needed) |
| Minimum operating system | Windows 10 22H2 (or your baseline) |

### Detection rules
Choose **Manually configure detection rules** › **+ Add** › **Registry**:

| Field | Value |
|---|---|
| Rule type | Registry |
| Key path | `HKEY_LOCAL_MACHINE\SOFTWARE\Company\DesktopBranding` |
| Value name | `Version` |
| Detection method | **Integer comparison** |
| Operator | **Greater than or equal to** |
| Value | `1` |
| Associated with a 32-bit app on 64-bit clients | **No** |

> - If you use `-CompanyFolder Contoso`, the key becomes `HKEY_LOCAL_MACHINE\SOFTWARE\Contoso\DesktopBranding`.
> - The install writes this key only after it finishes successfully. The script runs in 64-bit PowerShell, so the key is **not** under `WOW6432Node`. That's why the 32-bit option must be **No**.

### Dependencies / Supersedence
None needed. If you're replacing the previous version of this package, add it under **Supersedence** with **Uninstall previous version: No**. The new install cleans up the old scheduled tasks and helper script on its own.

### Assignments
| Goal | Assignment |
|---|---|
| New Autopilot devices | **Required** to a device group, e.g. a dynamic group of Autopilot devices: `(device.devicePhysicalIDs -any (_ -contains "[ZTDId]"))` |
| Existing devices with users working | **Required** to a device or user group. It applies in the signed-in user's session within a minute or so. A Settings window may flash briefly while the theme applies. |
| Self-service | **Available** to a user group (users install it from Company Portal) |

**Enrollment Status Page (optional):** to have the branding in place before the user first reaches the desktop, add **Desktop Branding** to **Block device use until these required apps are installed** in your ESP profile. It isn't required: users who sign in later still get the branding at their first sign-in.

---

## Parameters

### Install-DesktopBranding.ps1
| Parameter | Default | Description |
|---|---|---|
| `-CompanyFolder` (alias `-Location`) | `Company` | Image folder under `C:\Windows\Web\Wallpaper\`. Also used in the registry key names. |
| `-WallpaperImg` | `Company.jpg` | Wallpaper file name in `Wallpaper\` |
| `-LockscreenImg` | `CompanyLock.jpg` | Lock screen file name in `Lockscreen\` |
| `-ThemeFile` | first `*.theme` in `Theme\` | Theme file name in `Theme\` |
| `-AccentColor` | from the theme's `ColorizationColor` | Accent color as `#RRGGBB` |
| `-WindowsMode` | `Dark` | `Dark` / `Light` for Start, the taskbar and system UI. The Start/taskbar accent only works in **Dark**. |
| `-AppMode` | `Light` | `Dark` / `Light` for apps |
| `-NoAccentOnTitleBars` | off | Don't turn on the accent color on title bars and window borders |
| `-Version` | `1` | Value written to the detection key |

### Uninstall-DesktopBranding.ps1
| Parameter | Default | Description |
|---|---|---|
| `-CompanyFolder` (alias `-Location`) | `Company` | Must match the install |
| `-ThemeName` | read from install config | Theme file to remove, if the config is missing |

---

## Updating the branding

1. Replace the images or theme, and/or change parameters.
2. Rebuild the `.intunewin` and upload it to the **same** app (Properties › App package file).
3. Add `-Version 2` to the install command and change the detection rule value to `2`.

Devices then report "not detected" and reinstall. Users who are signed in get the new branding right away, which **overwrites anything they changed in the meantime**. New users get it at first sign-in.

---

## What gets changed

**Machine**
- `C:\Windows\Web\Wallpaper\<CompanyFolder>\`: the images
- `C:\Windows\Resources\OEM Themes\<theme>.theme`: the theme
- `C:\ProgramData\DesktopBranding\`: `Apply-UserBranding.ps1` and `branding.json`. Users can read these files but not modify them.
- `HKLM\SOFTWARE\<CompanyFolder>\DesktopBranding`: the detection key
- `C:\Users\Default\NTUSER.DAT`: default accent, palette, color mode, wallpaper and theme, plus a one-time **RunOnce** entry named `DesktopBranding`

**Per user** (the same values the Settings app writes)
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent`: `AccentPalette`, `AccentColorMenu`, `StartColorMenu`
- `HKCU\Software\Microsoft\Windows\DWM`: `AccentColor`, `ColorizationColor`, `ColorizationAfterglow`, `ColorPrevalence`, `EnableWindowColorization`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`: `SystemUsesLightTheme`, `AppsUseLightTheme`, `ColorPrevalence`
- `HKCU\Control Panel\Desktop`: `AutoColorization = 0`
- The lock screen image (set through the Windows lock screen API) and Spotlight turned off
- `HKCU\Software\<CompanyFolder>\DesktopBranding`: a record of what was applied, used by the uninstall

---

## Uninstall behavior

- For each signed-in user, each of the four items (theme, accent color, wallpaper, lock screen) is reset to stock Windows **only if it still matches what the package applied**. Anything the user changed themselves is left alone.
- Any pending first-sign-in RunOnce entries are removed, and the Default User profile is reset to stock (`aero.theme`, `img0.jpg`, Windows' default accent).
- The deployed theme, the image folder, `C:\ProgramData\DesktopBranding` and the detection key are deleted. Other OEM themes on the device are not touched.
- Users who aren't signed in during the uninstall keep their current look, but it is no longer managed.

---

## Logs & troubleshooting

| Log | Location |
|---|---|
| Install (includes the output of each user's run) | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-DesktopBranding.log` |
| Uninstall | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Uninstall-DesktopBranding.log` |
| Per user | `%LOCALAPPDATA%\DesktopBranding\Apply-UserBranding.log` |
| Intune agent | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` and `AppWorkload.log` |

Every step in the per-user log is marked `- OK` or `- FAILED: <reason>`. One failed step doesn't stop the others.

**Common issues**

| Symptom | Check |
|---|---|
| Accent is blue / not on the taskbar | `-WindowsMode` must be `Dark`. Make sure no Intune or GPO policy sets personalization colors. In the user log, look at the `SetUserColorPreference` and `Apply .theme file` lines. |
| Lock screen doesn't change | A **Personalization CSP** `LockScreenImageUrl` policy or the GPO "Force a specific default lock screen image" overrides it. |
| Nothing applied for a signed-in user | In the install log, look for `User task for … LastTaskResult=`. `0` means success. If there's no user log, the scheduled task couldn't start in that user's session. |
| New users don't get the branding | Look for a `DesktopBranding` value under the new user's `HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce`, and check their user log. Execution policy forced to `AllSigned` via GPO will block the unsigned scripts. In that case, sign them. |
| App shows "Not detected" after a successful install | Make sure the detection rule has **Associated with a 32-bit app on 64-bit clients = No** and that the key path matches `-CompanyFolder`. |

---

## Notes & limitations

- **Requirements:** Windows PowerShell 5.1, which is built into Windows 10/11. The scripts don't work in PowerShell 7 (the lock screen code needs 5.1).
- The accent is set through the same internal Windows function the Settings app uses. It isn't publicly documented, so a future Windows release could change it. If that happens, the registry values still apply and the user log shows a warning.
- Applying a `.theme` file goes through the Settings app, so a Settings window can appear briefly in the user's session. The script closes it.
