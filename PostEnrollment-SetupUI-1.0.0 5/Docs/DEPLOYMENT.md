# Deployment and your first-logon workflow

## Keep the current launch approach

This package intentionally retains your **SYSTEM + ServiceUI** setup. It does not register scheduled tasks, change enrollment policies, replace ESP, or alter your current first-logon trigger.

Stage the complete folder locally before your existing post-enrollment launch runs. The main window launches hidden child processes for the individual steps and polls their status. The window and workers inherit the original SYSTEM identity.

## Direct ServiceUI command

From your existing SYSTEM process, after the intended user's desktop exists:

```text
ServiceUI.exe -process:explorer.exe C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Program Files\YourCompany\DeviceSetup\Start-DeviceSetup.ps1" -ConfigPath "C:\Program Files\YourCompany\DeviceSetup\Config\Setup.json" -Live
```

Use your actual Windows/install paths. `Run-Live-ServiceUI.cmd` uses variable-based Windows paths and expects **x64 ServiceUI.exe**, which resolves System32 to 64-bit PowerShell. Do not pass a Sysnative path to an x64 ServiceUI process. To use it, place your existing x64 ServiceUI.exe in `Tools`, then invoke the CMD from your SYSTEM deployment mechanism. Double-clicking it as a normal user does not grant SYSTEM privileges; the live-mode identity check will reject that run by default.

The sample targets `explorer.exe`. Keep your existing session-selection logic if you support RDP, fast user switching, or multiple signed-in sessions. A process-name match is not a robust way to identify the intended employee on a multi-session computer.

## Installation location and permissions

Use a local protected folder such as `C:\Program Files\YourCompany\DeviceSetup`. Preserve SYSTEM/Administrators write access and ordinary-user read/execute access. Scripts, XAML, executable files, and JSON control SYSTEM execution and must not be writable by standard users. Do not run the live package from an employee-writable Downloads/Desktop folder.

Use your organization's approved script-signing/application-control approach. The sample commands use `ExecutionPolicy Bypass` for packaging convenience; this does not bypass WDAC/AppLocker or other enforcement policies.

The UI intentionally has no Open File, Open Log, or browser-launch buttons; diagnostics are displayed as text and can be copied. Users can minimize the window while work runs. Close/Alt+F4 is ignored until the run finishes; this is a workflow behavior, not a kiosk/security boundary.

## Intune integration

1. Package your completed folder with your normal Win32 packaging process.
2. Use your existing SYSTEM staging/install script to copy it to a protected local folder.
3. Detect that **the framework is staged**, using your existing version/file marker.
4. Let your existing first-desktop/after-ESP trigger launch the ServiceUI command.
5. Retain your completion/cleanup flow or use this package's completion records to avoid repeating successful work.

Do not make an ESP-blocking staging app wait for these desktop-only steps. ESP must be able to finish before the first-desktop launcher can run. The framework's staging detection and the final-setup completion result are separate concerns.

ServiceUI cannot show the popup before the target desktop/session exists. Keep your current enrollment-completion checks; a fixed sleep is not sufficient to identify the end of every provisioning scenario.

## State and log locations

Default live location:

```text
C:\ProgramData\Company\PostEnrollmentSetupUI\Company.DeviceSetup\
```

`StateDirectory` is the configured parent; `SetupId` is appended automatically. In SYSTEM live mode, SYSTEM and Administrators retain full control. By default, the interactive user gets read-only access to the new run folder, plus folder-only navigation permissions on the package and Runs folders. Completion-state files do not inherit that reader grant. The configured parent itself is not re-permissioned. See [log access and existing-run repair](HOTFIX8.md).

| File/folder | Purpose |
|---|---|
| Completed-1.0.0.json | Success records and declined options for that SetupVersion |
| Runs/<timestamp-id>/SetupUI.log | Controller status transitions |
| Runs/<timestamp-id>/stepXX-attempt-N.log | Per-attempt PowerShell transcript |
| Runs/<timestamp-id>/*.request.json | Parameters and paths given to the step worker |
| Runs/<timestamp-id>/*.progress.json | Latest live detail/percentage |
| Runs/<timestamp-id>/*.result.json | Worker completion/error details |
| Runs/<timestamp-id>/Results.json | Overall outcome and per-step results |

Demo runs use `%LOCALAPPDATA%\PostEnrollmentSetupUI\Demo\Runs`. They never update live completion state.

Completed work is skipped on later launches. With ResumeCompletedSteps=true, explicit declines are also remembered. If every enabled step is complete or declined with matching fingerprints, live mode exits without displaying a window. Incomplete/failed automatic work is reconsidered; incomplete/failed user-selectable work is offered unchecked again. This is once-per-device behavior, not once per employee profile.

Logs are not automatically deleted. Apply your normal endpoint log-retention policy. Never write credentials to messages, parameters, or transcripts.

## Offering optional apps again

Add **-ChooseOptional** to the existing SYSTEM + ServiceUI command to reoffer unfinished optional apps. Completed work stays completed. User choices are made before any step runs; automatic steps wait until Start setup is selected when choices are available. Old configurations without UserSelectable keep automatic execution. See [hotfix 4](HOTFIX4.md) for details.

The script sets a process-wide AppUserModelID before presenting the WPF window. Run it in its own powershell.exe process. Keep -WindowStyle Hidden to avoid showing a separate console window. The window icon can be customized with Branding.IconPath; the underlying executable remains powershell.exe.

## Resetting for a controlled retest

Use **-ResetState -Live** with the same SYSTEM launcher to archive the completion file and reconsider all enabled steps. This can repeat installations/configuration, so use it only when you intend a full retest. It does not uninstall anything. The normal in-window retry leaves successful steps untouched.

For a new intended setup revision, change `SetupVersion`. Changing only `SetupId` also creates a separate state namespace, so keep IDs stable unless you intend a new workflow.

## Return codes

| Exit code | Meaning |
|---|---|
| 0 | All required steps succeeded; optional failures may still be present in Results.json |
| 1 | A required step failed/skipped, or setup encountered a configuration/controller error |
| 3010 | Required work succeeded and a successful step requested reboot; no reboot is initiated |
| 1618 | Another instance of this package is already running |
| 2 from CMD wrapper | ServiceUI.exe is missing |

The default window remains open at the result screen until **Done** is selected; the parent launch does not finish until then. To close automatically after full success, set `AutoCloseSuccessSeconds`, for example 10. Warnings/failures remain visible. A reboot request is retained across launches until the detected Windows boot time changes.

## Updating the package

Keep your production scripts/config and review changes before replacing the framework. Retest using the actual ServiceUI command, standard-user desktop, screen scaling, app-control policies, and your intended post-ESP timing. Do not upgrade a package while one of its live steps is running.
