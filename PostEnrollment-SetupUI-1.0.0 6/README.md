# Post-enrollment Setup UI

**Version 1.0.0, cumulative hotfix 10 · Windows PowerShell 5.1 · WPF · Your existing SYSTEM + ServiceUI launch**

A configurable, Fluent-inspired first-desktop setup window. Keep your current post-enrollment trigger and replace the popup with this front end. Add your PowerShell code to individual step files; the window handles progress, animation, status, and results.

## Start here

**Hotfix 10:** [Enterprise first-logon setup](Docs/HOTFIX10.md) adds a complete ten-card profile for broad one-time Office removal, manufacturer-specific cleanup, device naming, Google apps with verified update checks, BitLocker audit, neutral WinGet skips and a mandatory final restart. First run **Run-FirstLogon-Demo.cmd** for the visual preview; then use **Run-Inventory-Live-ServiceUI.cmd** on a test PC to see what the live profile would target. The original configurations retain reminder-only reboot behavior. Read the guide before using the new live launcher.

**Hotfix 9:** [WinGet first with offline fallback](Docs/HOTFIX9.md) adds `Mode: "WinGetThenOffline"` for Company Portal and Notepad. WinGet runs in a limited-user task; SYSTEM verifies the user registration and handles offline provisioning if needed. Replace the five enterprise files listed in the guide, retain your payload paths, and update Mode in your JSON. A two-app pilot config and mocked orchestration tests are included.

**Hotfix 8:** [File Explorer log access](Docs/HOTFIX8.md) grants the signed-in user read-only access to new live run folders by default. Completion-state files retain their protected permissions. From hotfix 7, replace Start-DeviceSetup.ps1 and Core/Setup.Common.ps1. A separate tool can grant read access to existing runs.

**Hotfix 7:** [Company Portal SID detection](Docs/HOTFIX7.md) now queries AllUsers and matches the interactive user's Installed registration, avoiding the direct AppX -User lookup. From hotfix 6, replace EnterpriseSteps/Enterprise.Common.ps1. A detection-only test config is included; use it with -Live through your SYSTEM + ServiceUI launcher.

**Hotfix 6:** fixes reuse of an older UI model in a persistent PowerShell session and identifies mismatched UI files before opening the window. See [IsSelected startup fix](Docs/HOTFIX6.md). From hotfix 5, update Start-DeviceSetup.ps1 and Core/Setup.Common.ps1, and ensure UI/StepViewModel.cs and UI/MainWindow.xaml are from the same package. Keep your configuration and completed-step state.

**New enterprise step pack:** [Five installation/cleanup scripts and integration guide](Docs/ENTERPRISE-STEPS.md), `Config/Enterprise-Example.json`, `Run-Enterprise-Demo.cmd`, and Windows helper tests. From hotfix 4, copy EnterpriseSteps and update Core/Setup.Common.ps1 plus Start-DeviceSetup.ps1 for shared primary logging. Keep your existing customization. Installer payloads are supplied by you; the enterprise config contains clearly marked placeholders.

**Updating from hotfix 3 or earlier:** close the old window/PowerShell process and replace **Start-DeviceSetup.ps1**, **Core/Setup.Common.ps1**, **UI/MainWindow.xaml**, **UI/StepViewModel.cs**, and the new **UI/TaskbarIdentity.cs**. Merge any personal XAML edits into the new XAML. Keep your Config, Steps, Assets, and production launcher. New settings are optional, so old configurations keep their existing automatic-step behavior. No state reset or SetupVersion change is needed for this framework upgrade; execution fingerprints remain compatible. Update Tests/Invoke-SmokeTests.ps1 for the new checks and Run-Demo.cmd for a hidden-console demo launcher.

Hotfix 4 adds unchecked user-selectable steps, remembered declines, a configurable window icon, and a dedicated taskbar identity. The banner now matches the window background for transparent artwork. It includes the earlier brush, JSON-save, and banner-sizing fixes. See [the hotfix 4 guide](Docs/HOTFIX4.md) for copy/paste configuration examples and upgrade details.

1. Extract the entire ZIP to a local folder on a Windows test PC.
2. Double-click **Run-Demo.cmd**. No administrator rights are needed. Select either optional extra (or leave both unchecked), then choose **Start setup**. No step begins before this choice is submitted.
3. Watch the third step fail intentionally and the dependent fourth step become skipped. Expand its technical details, then choose **Retry unfinished**. The retry succeeds.
4. Edit **Config/Setup.json** to change your company name, welcome text, theme, logo/banner paths, and step labels.
5. Put your actual commands in **Steps/Step-01.ps1** through **Step-10.ps1**. Remove the placeholder `throw` in each step you implement.
6. Disable unused entries with `"Enabled": false`. Reorder the JSON objects to change execution order.
7. Run **Validate-Config.cmd**, then the Windows smoke tests in **Tests/Invoke-SmokeTests.ps1**.
8. Pilot live execution using your existing SYSTEM + ServiceUI workflow with **-Live**. See [deployment instructions](Docs/DEPLOYMENT.md).

**Safe by default:** launching Start-DeviceSetup.ps1 with no mode switch runs a simulation. Only **-Live** executes your step scripts. All ten supplied step scripts deliberately fail in live mode until you replace their placeholders. Demo mode never calls those scripts.

## What is included

| Feature | Behavior |
|---|---|
| 1-10 steps | Independent title, description, script, parameters, time limit, dependencies, and success codes |
| Modern appearance | Light/dark presets, rounded cards, accent color, readable typography, and status badges |
| Branding | Company name, welcome heading/message, optional logo, optional full-width banner, or both |
| Optional apps | Enabled + UserSelectable steps appear as unchecked choices before the run; users can select none |
| Window icon | Built-in setup icon or your ICO/PNG; separate taskbar grouping from ordinary PowerShell windows |
| Animated status | Spinning current-step indicator; completed checkmarks, failure crosses, and skipped markers |
| Progress | Overall steps-finished bar; optional per-step percentage and live message |
| Details | Expandable errors, elapsed times, run logs, and a copy-details button |
| Retry | Retry failed/skipped included steps; successful and unselected steps stay untouched |
| Resume | Remember successes and declined options per device, package ID, version, and execution fingerprint |
| Reliability | Separate worker process, responsive UI, time limits, duplicate-run prevention, and JSON results |
| Reboot reporting | Return 3010 by default; the new first-logon profile can explicitly schedule a mandatory restart |

This is custom WPF styled to resemble modern Windows. It is **not WinUI 3 or PSADT**, and it has no additional UI framework dependency.

## Files you will usually edit

| File | Purpose |
|---|---|
| Config/Setup.json | Main configuration; 5 automatic steps, 2 enabled user-selectable steps, and 3 disabled slots |
| Steps/Step-01.ps1 ... Step-10.ps1 | Your actual installation/configuration code |
| Assets/ | Your branding images and optional ICO/PNG window icon |
| UI/MainWindow.xaml | Optional advanced layout/style changes |
| Run-Live-ServiceUI.cmd | Optional convenience launcher; customize your existing launcher instead if preferred |

## Documentation

- [Configuration reference](Docs/CONFIGURATION.md): all settings and branding examples.
- [Writing steps](Docs/STEP-AUTHORING.md): success/failure rules, progress, parameters, installer examples.
- [Deployment and first-logon integration](Docs/DEPLOYMENT.md): ServiceUI, SYSTEM, Intune staging, state, and exit codes.
- [Testing and troubleshooting](Docs/TESTING.md): validation status, Windows checks, and common issues.
- [Enterprise steps guide](Docs/ENTERPRISE-STEPS.md): MSI, Company Portal, Office/OneDrive cleanup, Notepad, deployment modes and recommended checks.
- [Hotfix 4 guide](Docs/HOTFIX4.md): optional installs, icons, upgrade instructions, and examples.
- [Design preview](Docs/Design-Preview.html): HTML visual reference, **not a Windows runtime screenshot**.
- **START-HERE.html**: offline, formatted copy of this documentation.

## Quick commands

From an extracted package folder in Windows PowerShell:

```powershell
# Safe simulation; no step scripts run.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo

# Dark theme example.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo -ConfigPath .\Config\Dark-Demo.json

# All 10 steps enabled, to inspect the scrolling layout.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo -ConfigPath .\Config\All10-Demo.json

# Short optional-app demo: prerequisites and retry, with no app installs.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo -ConfigPath .\Config\Optional-Demo.json

# Configuration-only check; no UI or steps.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -ValidateOnly

# Windows tests; no app installs or ServiceUI invocation.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-SmokeTests.ps1
```

The demo/config-check CMD launchers choose Sysnative when called from a 32-bit process. The live wrapper instead expects x64 ServiceUI, which launches 64-bit PowerShell through System32. Run-Demo.cmd and the live wrapper hide the PowerShell console. The direct commands above leave a console visible for debugging; add -WindowStyle Hidden when needed. Always launch the UI in its own powershell.exe process because the taskbar identity is process-wide. The underlying executable remains powershell.exe in Task Manager.

## Scope and compatibility

- Target: Windows 10/11 x64 with Windows PowerShell 5.1 and the Windows WPF/.NET Framework components.
- The UI requires an STA session. PowerShell 7 is intentionally rejected for the UI to keep one supported host/runtime target.
- Your ServiceUI launcher, first-logon scheduling, and enrollment/ESP readiness checks remain your responsibility.
- This is **device-level** completion tracking. HKCU, APPDATA, and USERPROFILE refer to SYSTEM in a SYSTEM-run step, not the signed-in user.
- ServiceUI.exe and application installers are not included.
- No network calls, telemetry, package downloads, or built-in application changes are performed by the framework. Your live step scripts determine those actions.

## Verification status

Source parsing, configuration checks, XAML/XML structure, resource/element references, package links, and the HTML design reference are checked in the build environment. That environment is Linux, so **Windows PowerShell execution, WPF rendering, ServiceUI session presentation, and real installers have not been run here**. The included Windows smoke tests and pilot checklist cover those remaining checks.
