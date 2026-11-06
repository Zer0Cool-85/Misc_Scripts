# Testing and troubleshooting

## What has and has not been tested

The authoring environment is Linux. Validation here covers PowerShell source syntax with a tree-sitter parser, JSON/schema consistency, package paths/dependencies, XAML XML/resource/name references, documentation links, and the HTML design reference. These are useful static checks, not a substitute for the Windows WPF runtime.

**Not executed here:** Windows PowerShell 5.1, WPF XAML loading/rendering, the C# model under .NET Framework, ServiceUI session injection, SYSTEM execution, installer process termination, and actual application installs. No production-readiness or successful deployment claim is implied.

## Windows smoke tests

From the extracted folder:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-SmokeTests.ps1
```

The script parses the PowerShell files with Microsoft's actual PowerShell parser, loads all supplied configurations, exercises outcome/dependency logic, compiles the C# view model and taskbar helper (without invoking the shell API), and loads/measures the WPF layout with ten step models using the same theme-loading path as the application. It checks light, dark, all-ten, and custom-color cases, including brush types and the Done button's accent background. It also runs temporary worker fixtures for success, failure, explicit 3010, helper-based 3010, and progress updates. It does not display the main window, install an app, touch HKLM, or call ServiceUI. Its temporary files are removed afterward.

Hotfix 2 adds a JSON persistence regression check: create Results.json in a temporary folder containing spaces, overwrite it twice, verify the latest data and check for leftover files. The worker success fixture also publishes two progress updates and verifies the second one. These tests exercise the File.Replace branch that the original tests missed. Windows PowerShell converts a plain $null to an empty string for the backup filename; the fix passes [NullString]::Value to supply a true null. This preserves the existing replacement/retry behavior without creating a backup file. These runtime checks have not been executed in the Linux authoring environment.

Theme hotfix 1 applies configured colors to the XAML SolidColorBrush elements before loading the window. This avoids passing PowerShell-created objects through ResourceDictionary's object-valued indexer. The original smoke test loaded only the unmodified XAML and did not exercise this runtime theme path. The expanded Windows tests have not been executed in the Linux authoring environment.

## Visual pilot

1. Run `Run-Demo.cmd` as a regular user. Confirm both optional extras are unchecked. Select one and choose Start setup; required steps should then begin.
2. Confirm the window fits the display and remains responsive throughout the demo.
3. Confirm step 3 shows a failure and step 4 is skipped due to the dependency.
4. Expand the error; verify the message is legible and selectable.
5. Choose Retry unfinished. Only failed/skipped steps should run; all steps should then finish.
   Confirm no error popup appears and Results.json in the displayed log folder contains Outcome=Success and the latest step results.
6. Confirm Done closes the window. During active work, Close/Alt+F4 should leave the workflow running; minimize should work.
7. Run the Dark-Demo and All10-Demo configurations shown in README.md.
8. Test at your normal laptop resolution, 100/125/150/200% scaling, and your normal docked monitor setup. The step list should scroll, and the footer must remain reachable.
9. Add your actual logo/banner and inspect sizing, long welcome text, and long step labels. With Uniform + DownOnly, a small banner should remain centered without enlargement and a large banner should shrink without cropping. Check UniformToFill + Both only if you want the original fill/crop behavior. These banner layout checks require a Windows visual pilot; they were not executed here.

## Hotfix 4 selection and icon checks

The smoke tests exercise selection prerequisites, rejection without partial mutation, selecting no apps, exclusion from retry, remembered declines, ChooseOptional, legacy config defaults, and invalid required/optional dependencies. They also check that the built-in icon resolves while measuring the WPF window. These Windows tests are supplied but have not been executed here.

1. Run the short Config/Optional-Demo.json demo. Start with no options checked; only the automatic step should run and the other two should say Not selected without warning.
2. Relaunch the demo and select only the last option. Start setup should stay on the selection screen and explain the prerequisite. Select both, start, and retry the deliberately failed last option; only that failed option should retry.
3. Confirm choices lock after Start setup. Confirm elapsed time begins with execution, not while the user chooses. Verify keyboard selection with Tab/Space and both themes.
4. Under your actual SYSTEM + ServiceUI launcher, use harmless live step scripts. Decline an app, finish required work, then relaunch: the window should not reappear for the matching declined app. Relaunch with -ChooseOptional and verify it is offered unchecked, while completed work is retained.
5. Test a configuration containing only user-selectable steps and choose none: progress should finish without division by zero. Test an interrupted selected app: on relaunch it should be offered unchecked.
6. Check the title-bar, taskbar and Alt+Tab icon using the default and your own multi-resolution ICO/PNG. Launch a separate ordinary PowerShell window and confirm taskbar grouping is separate. Validate both the normal-user demo and SYSTEM + ServiceUI. The PowerShell console should be hidden when using the supplied launchers. Task Manager will still show powershell.exe.
7. Check your transparent banner against light and dark window backgrounds. CanvasBrush should blend it into the window without changing the accent controls.

## SYSTEM/ServiceUI pilot

1. Work on a disposable/test device with your normal application-control policies.
2. Put a harmless real action in one step, such as verifying an existing file. Disable the other steps. Keep RequireSystemForLive true.
3. Stage the full package in a protected local folder and use your existing SYSTEM + ServiceUI first-desktop trigger.
4. Confirm the expected logged-on session sees the UI and the step transcript reports the expected identity.
5. Verify success, a deliberate throw, a declared dependency failure, and an optional failure.
6. Run the package again. Matching successful steps should be skipped; if all work is complete, no window should appear.
7. Change the test step's contents and rerun. Its fingerprint should change and the step should run again.
8. Test a short time limit with a harmless sleeping step. The worker should be terminated, remaining steps skipped, and in-window retry hidden.
9. Test reboot-required behavior using a harmless `exit 3010` step. With EnforceFinalRestart omitted or false, confirm no reboot is initiated and the caller receives 3010 after Done.
10. Test an interrupted run/logoff and a second simultaneous launch. Confirm retry/resume behavior and the 1618 duplicate-instance result.

Only then add the real application/configuration work and validate each action's detection and idempotence. Custom actions can impose limitations that the UI cannot infer.

## Troubleshooting

| Symptom | Check |
|---|---|
| Optional app runs automatically | Required=false only affects failure handling. Set Enabled=true, UserSelectable=true, Required=false to offer an unchecked choice. |
| Declined optional app is not offered again | Add -ChooseOptional to the existing live launch; this retains completed work. |
| PowerShell icon still appears | Confirm the new UI/TaskbarIdentity.cs and XAML are deployed; launch in a fresh dedicated powershell.exe with -WindowStyle Hidden. Check whether the icon belongs to a separate console or an old pinned shortcut. Task Manager still identifies the host as powershell.exe. |
| No window when launched by Intune | Confirm the call occurs after desktop readiness; confirm ServiceUI/session target and use your existing known-good launcher. A direct SYSTEM launch without ServiceUI is not interactive. |
| Live run says SYSTEM is required | ServiceUI does not elevate an ordinary user. Invoke from your existing SYSTEM task/deployment. |
| Powershell host/STA error | Use 64-bit Windows PowerShell 5.1 with -STA. Use Sysnative from a 32-bit caller. |
| Window closes immediately / hidden startup failure | Run Validate-Config.cmd, then launch the PS1 from a visible PowerShell console. Check JSON paths, image existence, runtime version, and application-control policy. |
| `#FF2563EB is not a valid value for property Background` | Install theme hotfix 1: replace Start-DeviceSetup.ps1 and Core/Setup.Common.ps1 together. Keep configured colors as #RRGGBB. The FF prefix in the error is WPF's opacity channel; the hex color is valid. |
| `Exception calling "Replace" with "3" argument(s): The path is not of a legal form` after retry | Install hotfix 2 by replacing Core/Setup.Common.ps1. The JSON writer needs [NullString]::Value for File.Replace's backup filename. The original generic popup title can say "could not start" even for a later runtime error. |
| A supplied step fails instantly | Placeholder scripts deliberately throw until you replace their code. |
| Script works interactively but fails here | Check SYSTEM's profile, working directory, network identity, permissions, mapped drives, and bitness. Use local files and explicit paths. |
| State did not rerun a completed step | Match SetupId/SetupVersion; inspect the completion record. For intentional full retest use -ResetState; for a new revision bump SetupVersion. |
| Changed installer file did not rerun a step | External payload/helper contents are not fingerprinted. Bump SetupVersion or change the step/parameters; keep real detection in your script. |
| UI reports success after an EXE failed | Check that every native result is tested; prefer Invoke-SetupProcess. Outputting false/error text is not a failure signal. |
| Step remains running after its installer seems done | Ensure your script returns and all waited-for child processes exit. Inspect the transcript and installer process tree. |
| Timeout still leaves installer activity | Some installs continue inside a Windows service. Inspect/recover that operation before restarting the workflow. |
| Progress jumps or shows 100% with a failure | Overall progress counts finished steps, including failed/skipped work. Status color and text indicate the outcome. |
| Retry button is missing | AllowRetry must be true; a timeout/controller error intentionally disables retry. |
| Dark content, light title bar | The content theme is custom WPF; the native title bar is left to Windows. |
| Banner appears enlarged, zoomed or cropped | Use hotfix 3 with Branding.BannerStretch=Uniform and BannerStretchDirection=DownOnly (the defaults). Unused header space now matches the window background. Lower BannerHeight to reduce vertical space. |
| Completion state is unreadable | Inspect/archive the state file explicitly. The framework stops rather than silently repeating production actions. |

## Sources used for platform behavior

- [Microsoft: Window.Icon](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.icon)
- [Microsoft: SetCurrentProcessExplicitAppUserModelID](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-setcurrentprocessexplicitappusermodelid)
- [Microsoft: WPF threading model](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model)
- [Microsoft: WPF Stretch modes](https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.stretch)
- [Microsoft: WPF StretchDirection and DownOnly](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.stretchdirection)
- [Microsoft: File.Replace and the nullable backup filename](https://learn.microsoft.com/en-us/dotnet/api/system.io.file.replace?view=netframework-4.8.1)
- [Microsoft: NullString passes null to a .NET string parameter](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.nullstring)
- [Microsoft: WPF Control.Background requires a Brush](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.control.background?view=netframework-4.8.1)
- [Microsoft: SolidColorBrush and hexadecimal color formats](https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.solidcolorbrush?view=netframework-4.8.1)
- [Microsoft: WPF animation overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/graphics-multimedia/animation-overview)
- [Microsoft: Start-Process, Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1)
- [Microsoft: Start-Transcript, Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript?view=powershell-5.1)
- [Microsoft: automatic variables and LASTEXITCODE](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables?view=powershell-5.1)

The window, configuration format, step runner, and documentation in this package are a custom implementation, not a Microsoft or PSADT product.

## Enterprise step pack (hotfix 5)

Run Tests/Invoke-EnterpriseHelperTests.ps1 in a fresh 64-bit Windows PowerShell process. It uses temporary files and mocked app deployment commands to check concurrent log writes, user-scoped app health detection, provisioning-versus-registration, idempotency, and missing-license rejection. It makes no live app, registry or scheduled-task changes. These tests have not been run in the Linux authoring environment. Follow the separate Windows pilot matrix in [Enterprise steps](ENTERPRISE-STEPS.md) for real MSI, AppX, Office and OneDrive validation.

## UI model loading (hotfix 6)

The Windows smoke suite now loads a simulated legacy model first, verifies the current source loads independently, checks unchanged/changed source caching and old-file diagnostics, and initializes the five automatic enterprise steps. These regression tests are supplied but not executed in the Linux build environment. See [Hotfix 6](HOTFIX6.md).

## Log access (hotfix 8)

Run Tests/Invoke-LogAccessTests.ps1 from elevated Windows PowerShell for temporary-directory NTFS inheritance and read-only checks. It does not touch production state or logs. These Windows tests are supplied but unexecuted in the build environment. Verify ordinary File Explorer can open logs and cannot save edits. See [Hotfix 8](HOTFIX8.md).

## WinGet fallback (hotfix 9)

Run `Tests/Invoke-WinGetFallbackTests.ps1` in a fresh 64-bit Windows PowerShell 5.1
process. It uses mocks to check both apps: healthy-app skip, verified WinGet
success, native failure with an app now present, success without registration,
offline fallback/verification failure, inventory errors and uncertain cancellation.
It does not execute installers or scheduled tasks. These runtime tests are supplied
but were not executed in the Linux build environment.

Use `Config/StoreApps-WinGet-Example.json` for the focused live pilot after staging
its payloads. See [Hotfix 9](HOTFIX9.md) for upgrade instructions, the test matrix,
user-side logs, policy handling and the distinction between Demo and Live.

## Enterprise first-logon setup (hotfix 10)

Run `Tests/Invoke-ProvisioningTests.ps1` and `Tests/Invoke-EnterpriseWorkflowMocks.ps1` in fresh x64 Windows PowerShell 5.1 processes. The first covers naming, encryption verdicts, skip/resume, and restart scheduling with a mocked native process. The second covers Office inventory/removal/receipts, WinGet denial, and Google updater state transitions with platform operations replaced by fixtures. Neither restarts or installs anything. Then pilot the [live scenarios](HOTFIX10.md) on a disposable enrollment device. Static validation in this build does not substitute for Windows runtime verification.
