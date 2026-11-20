# Device rename remediation 1.2.3 — generic Windows names only

This update permits rename remediation only when no computer rename is pending and the active name matches **DESKTOP- or LAPTOP- followed by one or more ASCII letters/digits**. Matching is case-insensitive and the total name is limited to 15 characters. A nonmatching custom name is left alone even if it does not follow the organization's naming convention.

Version 1.2.3 handles a missing notification setting in the user helper. A missing notifier produces an explicit error. A missing setting on a valid notifier permits one normal Windows submission. A reported disabled setting is logged and ends the attempt. The helper records the build, process ID, mode, failure stage, file, line, and PowerShell error ID in the user's Toast.log. A submitted toast can still be suppressed by Windows.

For an already pending rename, extract this version on the pilot PC and run the forced reminder command in **Pilot and troubleshooting**. A previous release recorded a launch even if the user helper subsequently failed. During normal evaluation, this version retries a previous payload once if Task Scheduler recorded exit code 1 for that user's task and the same name transition. A successful or snoozed reminder keeps its history.

Version 1.2.2 addresses two failures visible in a mixed deployment. An installer logging `Could not send/store a reminder ... Property Session1 does not exist` is using the older reminder implementation. An entry from detection ending in `(18,8):UserId:` points to Task Scheduler rejecting the personal task principal. The rename can already be staged when either notification fails.

The task now runs on demand in the selected interactive session. The toast offers **Snooze** (15 minutes, 1 hour, or 4 hours) and **Restart now**. Existing notification history still suppresses duplicate reminders for the same pending rename. For a pilot with the rename already staged, go straight to **Pilot and troubleshooting** to requeue the reminder.

This ZIP contains source files, not a prebuilt `.intunewin`. Generated-name rules, requirement output, audit mode and rename receipts are retained. The generic-name gate is shared by the requirement and installer.

## Reproduce a requirement result on a pilot PC

Extract the ZIP and run the following in 64-bit Windows PowerShell from its root while the intended console user is signed in.

```powershell
.\Tools\Test-RenameRequirement.ps1
```

The probe reads the live active and configured names, prints the active name's exact UTF-16 code units, reports the pending flag, evaluates eligibility, and prints the SHA-256 of the local standalone requirement. It does not create a task, touch the receipt, or stage a rename. Blank account and AD fields mean the decision returned before querying CIM. For an installer preview, run `Source\Install.cmd -AuditOnly`.

For `DESKTOP-ABC123`, expect length 14, hyphen `U+002D`, and `generic=True`. With the same configured name, an eligible console account, and no AD domain join, expect requirement integer 1. If the configured value alone is generic, the pending check takes precedence. After uploading 1.2.3, correlate the latest UTC timestamp and component in the log with the app GUID in AppActionProcessor.log or AppWorkload.log. Both rule uploads and the installer content are independent.

```powershell
$logs = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
Get-Content (Join-Path $logs 'DeviceRenameRemediation.log') -Tail 30
```

In 1.2.3 a fresh requirement or installer evaluation logs `build=1.2.3` together with the registry inputs and match result. The trace labels `processName` with the COMPUTERNAME environment value inherited by that process. The registry active name is used for the decision. An old timestamp indicates an earlier evaluation. A new requirement decision without the build trace warrants checking which standalone rule was uploaded.

## Retry one Required Win32 app on the lab PC

Start with **Company Portal > Settings > Sync**, then check the app GUID and timestamp in AppWorkload.log. A check-in requests policy and evaluation. A valid detection, unmet requirement, pending rename, or existing retry delay can still prevent an install. Check the pilot probe first. To repeat a completed rename, restore a generic-name VM checkpoint or rename the pilot back and reboot before testing.

To inspect local app-specific cache records use an elevated 64-bit Windows PowerShell and the **Win32 app object's GUID** from the Intune app URL. Run the Apply command between installations on a pilot PC.

```powershell
$appId = Read-Host 'Paste the Intune Win32 app GUID'
.\Tools\Reset-IntuneWin32AppTestState.ps1 -AppId $appId
.\Tools\Reset-IntuneWin32AppTestState.ps1 -AppId $appId -Apply
```

The first command with the script previews the entries. Apply briefly stops the device-wide IME service, rescans, backs up matching records under the invoking account's LocalAppData\IntunePilotBackups, removes them, and starts IME to check in. Eligible Required apps may install during that check-in. All GUID-named assignment contexts are examined by default. Use `-ContextId` with a GUID from the preview to narrow the operation.

The tool targets exact app GUID records (including numeric revision suffixes) and individually attributable GRS values or child keys under Win32Apps in the 64-bit registry. Shared GRS buckets, other apps, assignments, actual detection artifacts, rename receipts, and toast history stay in place. Unrecognized agent layouts and shared cooldowns can still require waiting. With no matching records, the tool reports that result and leaves the service running as found. A backup manifest accompanies the exported key subtrees and individual saved registry values.

If a fresh Required assignment is needed immediately, create a separate pilot-only Win32 app object, upload the same content and rules, and target only the pilot PC. Use a single active rename assignment on that PC. An Available assignment to your test user is handy for testing the installer and toast interactively. Final validation should use Required to reproduce automatic execution and timing.

[Microsoft IME check-in guidance](https://learn.microsoft.com/en-us/intune/device-management/tools/management-extension-windows) · [Microsoft Win32 troubleshooting logs](https://learn.microsoft.com/en-us/intune/app-management/deployment/troubleshoot-win32) · [Community investigation of app-specific retry state](https://call4cloud.nl/retry-failed-win32app-installation/)

## Upgrade the existing Intune app

1. Build a new `.intunewin` from this bundle's `Source` folder and replace the app's package content.
2. **Replace BOTH uploaded rule scripts:** `Intune\Requirement-RenameComputer.ps1` and `Intune\Detect-RenameComputer.ps1`. Repackaging Source alone does not update those rules.
3. Keep **System** install context, **64-bit** rule execution, and the settings below.
4. Pilot on a signed-in Windows 11 x64 endpoint with a pending rename.

The two rule scripts embed the user helper, so they can stage it and create its task **even when the requirement blocks installation**. Existing rename receipts do not need to be deleted.

## Requirement behavior

| State | STDOUT | Exit code | Action |
| --- | --- | --- | --- |
| Active/configured computer names differ | `0` | `0` | Queue user toast once; block another rename |
| No pending rename; current name is not generic | `0` | `0` | Leave any custom name alone |
| No pending rename; DESKTOP-/LAPTOP- name; usable console account | `1` | `0` | Permit installer to rename |
| No console user, unsupported account format, or AD domain join | `0` | `0` | Defer/exclude; log the reason |
| Registry/CIM read fails | Empty | `1` | Fail evaluation; do not assume rename eligibility |

Pending rename compares the `ComputerName` values at:

```text
HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName
HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName
```

This is not a general Windows Update/file-rename pending-reboot check. Detection still requires the saved receipt and its matching, compliant configured name. It can succeed before or after reboot. A pre-existing custom-named PC without a receipt is not claimed as installed; the requirement is unmet. Portal status may reflect cached/earlier evaluations.

The eligibility pattern is `\A(?:DESKTOP|LAPTOP)-[A-Z0-9]+\z`, with case-insensitive matching and a separate 15-character length check. The suffix length is not fixed at seven. An empty suffix, spaces, underscores or additional hyphens do not match. This checks the name's format, not how Windows or an administrator originally chose it; a manually chosen name with the same pattern also qualifies.

| Example active name, with no pending rename | Requirement result |
| --- | --- |
| `DESKTOP-A1B2C3D` | Eligible if existing user/domain checks pass |
| `LAPTOP-7X8Y9Z0` | Eligible if existing user/domain checks pass |
| `desktop-abc1234` | Eligible; case-insensitive |
| `JDOE-LT-R7` | Not applicable |
| `CORP-LT-001` | Not applicable, even though it differs from the generated-name convention |
| `ACCOUNTING01` | Not applicable |

The installer independently enforces this gate. If a different custom name appears after requirement evaluation, it does not rename it. It defers with 1618 when it cannot detect a valid completed rename; the next requirement evaluation excludes the custom name.

## Task and toast lifecycle

- Under SYSTEM the scheduler obtains the SID directly from the active session token. The elevated pilot command uses the owner SID of Explorer in that session. The SID identifies the reminder recipient and its history.
- SYSTEM or the elevated diagnostic registers `DeviceRename-RebootToast-<SID>` with the well-known local Users group as principal and limited privileges. It starts the task once through Task Scheduler's `RunEx` method with the target session ID. The helper checks its actual SID and session before showing the toast.
- There are no time or logon triggers. The task definition stays available for inspection and reuse until package uninstall. Battery operation is allowed and execution is limited to two minutes.
- The user helper creates its per-user notification identity, protocol handler, and **IT Device Restart** Start menu shortcut. It submits a native toast and exits; no process waits for a click.
- **Windows handles Snooze.** No recurring task is created. Repeated Intune evaluations do not replace the snoozed toast.
- The initial launch is recorded once per user, active/target name pair and helper version. Dismissing the toast does not schedule another initial reminder. A new rename or explicit forced reminder can queue a new task.
- The toast expires after 24 hours and requests expiration on reboot. With no active user, a later Intune evaluation can try again; this is not an at-logon agent.

Toast text:

> Your PC needs a restart to finish a device-name update. Save your work before choosing Restart now.

Restart now uses the `devicerename-reboot:` protocol to launch the helper in the user's session. The handler validates the current random token, expiry, preview/consumed flags, and latest active/configured names. A stale notification cannot restart a PC after its pending rename clears or changes. Clicking the toast body only reopens the reminder.

The command is **`shutdown.exe /r /t 0` without `/f`**. A positive timeout would imply forced application closure. Save work first; applications can block a normal restart. The user needs the normal Windows **Shut down the system** right. This does not elevate or bypass a policy denying that right.

User/policy notification settings, Do not disturb/Focus and a locked desktop can hide a banner. A queued task is not proof of visible delivery. Application-control policy must allow the script, Add-Type, WinRT and protocol activation. No BurntToast module or ServiceUI is required.

## Session1 bug fix

Version 1.0.0 requested a specific history value before it existed. The provider error aborted the reminder attempt. The original mocked test treated that as only a suppressible error and missed the failure.

This version reads the existing key with `Get-ItemProperty`, then checks `.PSObject.Properties[...]` for the optional value. Missing history is a normal first run. New records use `User_<SID>` values; old Session1 values can be left in place and are ignored. The regression test now models a terminating missing-value error.

## Package and configure

Use the current [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool). With this ZIP extracted to `C:\Intune\DeviceRename`:

```powershell
.\IntuneWinAppUtil.exe -c "C:\Intune\DeviceRename\Source" -s "Install.cmd" -o "C:\Intune\DeviceRename\Output" -q
```

Keep the tool and output outside Source. Upload the resulting `.intunewin`.

| App setting | Value |
| --- | --- |
| Install command | `Install.cmd` |
| Uninstall command | `Uninstall.cmd` |
| Install behavior | **System** |
| Restart behavior | **No specific action** |
| Allow available uninstall | **No** |
| Installation time | 5 minutes |
| Architecture | x64; x86/ARM64 are outside this pilot scope |
| OS | Supported Windows in your environment; toast APIs require Windows 10 1903+ |

| Return code | Intune mapping | Meaning |
| --- | --- | --- |
| `0` | Success | Compliant/no remaining reboot |
| `3010` | **Success** | Rename staged; custom toast asks for restart |
| `1618` | Retry | User/name is no longer eligible when installer runs |
| `1` | Failed | Rename/verification/receipt failure |

**Change 3010 from Soft reboot to Success for this custom-toast-only setup.** This gives up Intune's built-in reboot-needed status for the app. Independent organizational restart policies still apply. If you choose Intune's own reboot handling, review restart settings and expect possible duplicate notices.

| Requirement setting | Value |
| --- | --- |
| Type/script | Script / `Intune\Requirement-RenameComputer.ps1` |
| Run as 32-bit | **No** |
| Logged-on credentials | **No** |
| Comparison | **Integer / Equals / 1** |
| Signature check | No for unsigned pilot; sign first if your policy requires it |

| Detection setting | Value |
| --- | --- |
| Type/script | Custom script / `Intune\Detect-RenameComputer.ps1` |
| Run as 32-bit | **No** |
| Signature check | Match your signing policy |

Assign Required to a small device pilot after the intended owner signs in. Do not make this user-dependent rename an Autopilot ESP blocking app.

## Retained generated-name and detection rules

- Accepts `JDOE-LT` and `JDOE-LT-R7`, case-insensitively. Prefix is 2–9 ASCII letters/digits starting with a letter; total name is at most 15 characters.
- Tokens remain LT, DT, VM, SRV, PC. New names use detected chassis and a two-character random A–Z/0–9 suffix by default. `Install.cmd -NoRandomSuffix` omits it; `Install.cmd -DeviceType LT` forces LT.
- Prefix budget is `Min(9, 15 - suffix.Length)`: nine for `-LT-XX`, eight for `-SRV-XX`.
- Identity remains the **console user**, not Intune primary user. Supported formats: `DOMAIN\first.last`, `AzureAD\first.last`, `first.last@domain`. Unparseable accounts defer; a parseable technician account can still be used, so target the owner session.
- AD domain-joined devices are excluded because no domain rename credentials are supplied. Entra/Intune display names are not directly edited.
- Output/detection matching checks format, not ownership/chassis accuracy. This output pattern no longer decides which existing devices are eligible for rename. Two random characters do not guarantee fleet-wide uniqueness.
- The installer rechecks state/user before renaming, uses terminating error handling, verifies the rename result and configured name, and writes a receipt only after verification.

## Customize and rebuild

Edit `Source\User-RebootToast.ps1` for toast text and snooze choices, or `Source\Naming.Common.ps1` for naming/task settings. Then run:

```powershell
.\Build-UploadScripts.ps1
```

This updates the helper embedded in the common file and both Intune scripts. The base64 is a copy of the readable helper, not an encoded execution command; tasks execute the staged `.ps1` by path. Its embedded hash is verified before staging.

If signing, sign the user helper first, rebuild to embed those signed bytes, then sign the common/installer and rule scripts. Repackage Source and replace both rule uploads. Supplied files are unsigned.

## Pilot and troubleshooting

Preview the rename without changing it or scheduling a toast:

```powershell
.\Source\Install.cmd -AuditOnly
```

Preview the toast in the **signed-in user's 64-bit Windows PowerShell 5.1**. It creates the user's registration/shortcut, but Restart now is inert:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Source\User-RebootToast.ps1 -Preview
```

Preview replaces that user's current toast/token. Requeue a real reminder afterward if needed. Normal task execution registers the protocol/shortcut against the protected staged helper.

On a PC with a pending rename, queue a fresh reminder as **SYSTEM or an administrator** using 64-bit Windows PowerShell. This bypasses the once-only record but never renames or restarts the PC itself:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Source\Schedule-PendingRenameToast.ps1 -ForceReminder
```

Look for a fresh `build=1.2.3` entry followed by `Dispatched` in the machine log. A registration or dispatch error identifies the failed step, returns exit 1 from the manual command, and leaves the attempt eligible for a retry. The Intune requirement still blocks a second rename. From the target user's own PowerShell, check for `Toast submitted` in their log. The forced reminder is live. Choose **Snooze** to keep the rename pending for more tests.

| Evidence | Location |
| --- | --- |
| SYSTEM log | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DeviceRenameRemediation.log` |
| User toast/action log | `%LOCALAPPDATA%\DeviceRenameRemediation\Toast.log` for the target user |
| Task | `DeviceRename-RebootToast-<SID>` |
| Machine state | `HKLM\SOFTWARE\DeviceRenameRemediation` |
| User token | `HKCU\Software\DeviceRenameRemediation\Toast`, value Current |
| Helper | `C:\Program Files\DeviceRenameRemediation\User-RebootToast.ps1` |

Check task Last Run Result and the user log. If first launch failed or the user signed out during dispatch, correct the issue and use `-ForceReminder`; this is deliberately not a recurring retry service. Notification suppression can still hide a successfully submitted toast.

Windows pilot checklist:

1. Pending rename queues a task for the intended SID; requirement remains output `0` / exit `0`.
2. First run succeeds with no saved notification-history value.
3. Task shows the built-in Users group, limited run level, and no triggers. The signed-in user sees both toast buttons.
4. Snooze returns at the selected interval after the launch task exits.
5. Repeated requirement/detection checks do not replace the snoozed toast.
6. Preview Restart now is inert.
7. On a disposable endpoint with work saved, the real button restarts normally and activates the new name.
8. A stale token after reboot or a changed rename target cannot cause another restart.

Run offline tests in separate processes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-NamingLogic.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-ToastActions.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-PilotCacheSelection.ps1
```

Validation completed on PowerShell 7.4.6/Linux: **the naming, requirement, toast/action and pilot cache selection suites passed**. Tests exercise PowerShell parsing, C# compilation, naming/state transitions, missing-value handling, task definitions, toast XML, URI validation, preview safety and restart guards. Windows API calls, staging, Task Scheduler, display and shutdown are mocked. **A Windows PowerShell 5.1/Intune pilot remains required.**

## Cleanup

Remove Required assignments first. While the helper is present, run this as each user to remove their toast, protocol, token and Start menu shortcut:

```powershell
& "$env:ProgramFiles\DeviceRenameRemediation\User-RebootToast.ps1" -Mode Cleanup
```

Then `Uninstall.cmd` removes machine tasks, helper and HKLM state; logs remain. Offline users' HKCU/shortcut entries are not automatically removed by machine uninstall. Uninstall does not roll back or cancel a rename.

## References

- [Intune Win32 requirements/detection/return codes](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask)
- [Launch a task in a specific interactive session](https://learn.microsoft.com/en-us/windows/win32/taskschd/registeredtask-runex)
- [Task settings and expiration](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset)
- [Toast buttons and snooze](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-content)
- [Desktop toast AppUserModelID shortcut](https://learn.microsoft.com/en-us/windows/win32/shell/enable-desktop-toast-with-appusermodelid)
- [Expiration on reboot](https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotification.expiresonreboot)
- [Shutdown and force-close behavior](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown)
- [Get-ItemProperty](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-itemproperty?view=powershell-5.1)
