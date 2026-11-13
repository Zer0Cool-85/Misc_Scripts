# Device rename remediation for Intune Win32

Version 1.0.0 | Prepared November 13, 2026 | Windows PowerShell 5.1

This source bundle checks for an existing pending computer rename, reminds signed-in users to restart, and renames eligible endpoints to a first-initial/surname pattern. It includes the files and settings needed to create an Intune Win32 app. **The ZIP is not an `.intunewin` file**; run Microsoft's Content Prep Tool on Windows as shown below.

## Behavior

The requirement is configured as **Integer / Equals / 1**. A normal eligibility decision always exits with code **0**; the single number written to STDOUT determines whether the requirement is met.

| Device state | Requirement STDOUT | Exit code | Action |
| --- | --- | --- | --- |
| A computer rename is already pending, regardless of the target's format | `0` | `0` | Send a restart reminder if a user session is available; block installation |
| No pending rename; active name already matches | `0` | `0` | Block installation; leave the name alone |
| No pending rename; name does not match; usable console user | `1` | `0` | Allow the installer to run |
| No console user, account format cannot be parsed, or AD domain-joined | `0` | `0` | Defer/exclude and log the reason |
| Registry or CIM query fails | No output | `1` | Fail evaluation; never assume renaming is safe |

Pending rename detection compares the `ComputerName` values at:

```text
HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName
HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName
```

A case-insensitive difference indicates a staged computer-name change. This check intentionally does not treat `PendingFileRenameOperations` or a Windows Update reboot as a computer rename.

An unmet requirement makes an initially unevaluated, undetected app inapplicable. A requirement script cannot directly assign a portal status, and Intune can retain earlier results. Detection requires both this package's receipt and the matching configured name, so a device that was compliant before deployment is not immediately claimed as installed. After this package runs, detection can succeed before or after the restart. Do not use the portal's single Installed/Not applicable label as a pending-reboot inventory.

## Naming rules and identity assumptions

- Existing names may have no random suffix or exactly two alphanumeric suffix characters, such as `JDOE-LT` and `JDOE-LT-R7`.
- The prefix has 2–9 ASCII letters/digits and begins with a letter. The total name must be 15 characters or fewer. Matching is case-insensitive.
- As in the supplied script, device tokens include `LT`, `DT`, `VM`, `SRV`, and `PC`. New names use detected chassis type by default.
- New names include a two-character random suffix by default. `Install.cmd -NoRandomSuffix` omits it.
- The prefix budget is `Min(9, 15 - suffix.Length)`. `-LT-XX` allows nine prefix characters; `-SRV-XX` allows eight.
- A matching format is sufficient. This does not verify that the prefix belongs to the current or Intune primary user, or that an existing LT/DT token matches the actual chassis.
- The account source remains `Win32_ComputerSystem.UserName`, meaning the console user, not the Intune primary user. It accepts `DOMAIN\first.last`, `AzureAD\first.last`, and `first.last@domain`.
- Accounts such as `AzureAD\JohnDoe`, `first.middle.last`, shared logins, technician logins, and service accounts cannot be assumed to identify the intended device owner. Unparseable accounts defer. A parseable technician account can still be used: target assigned-user devices after the intended owner signs in.
- Accents that decompose into ASCII letters are normalized, and apostrophes/hyphens are removed. Names that cannot yield an ASCII initial and surname defer rather than being guessed.
- This package targets Entra-joined/workgroup clients. AD domain-joined computers are excluded because the script does not supply domain rename credentials. It does not modify Entra/Intune display names directly or an Autopilot device-name template.
- Two random base-36 characters provide 1,296 suffixes **per identical prefix/type**. This reduces collisions but does not guarantee fleet-wide uniqueness; no directory lookup is performed. Use a centrally assigned identifier if uniqueness is a hard requirement.

To accept only LT names, change `$script:AllowedDeviceTypes` to `@('LT')` in `Source\Naming.Common.ps1` and both `Intune` scripts. Target laptops, or use `Install.cmd -DeviceType LT` if LT is intentionally your universal device token. Keep all three copies consistent.

## Restart popup

The popup says:

> Your PC has a pending computer name change. Please save your work and restart your PC to finish applying it. Select Start > Power > Restart. Clicking OK closes this message; it does not restart your PC.

The implementation uses Windows `WTSSendMessageW` to address active console/RDP user sessions from SYSTEM. It does not use a hidden Session 0 MessageBox, require ServiceUI, or require a logged-on user token. It sends the dialog asynchronously so Intune does not wait for a click. The requested dialog timeout is 300 seconds.

Requirement and detection both check for a pending rename and share the same notification throttle. The installer also calls the reminder after staging a new rename. This avoids depending on Intune always executing requirements before detection, while preventing duplicate popups in the same evaluation cycle.

The default minimum interval is **four hours per session/account/name pair**. Change `$script:ReminderHours`, `$script:PopupTitle`, `$script:PopupMessage`, or `$script:PopupTimeoutSeconds` in all three copies if needed. Zero reminder hours prompts on every evaluation and can produce multiple messages during a single app evaluation.

This is an evaluation-triggered reminder, not a scheduled reminder service. If nobody is signed in, or the device is offline, there is no visible message at that time. A later app evaluation can try again. A locked session may not expose the popup until unlock. A popup failure is logged and never permits another rename over a pending one.

The scripts never call a reboot command. The default Intune settings below use the custom popup only.

## Package on Windows

1. Extract this bundle, for example to `C:\Intune\DeviceRename`.
2. Obtain the current [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool).
3. In a terminal, run:

```powershell
.\IntuneWinAppUtil.exe -c "C:\Intune\DeviceRename\Source" -s "Install.cmd" -o "C:\Intune\DeviceRename\Output" -q
```

Upload the resulting `.intunewin` file. Keep `Output` outside `Source`. Only the files in `Source` are packaged; the scripts in `Intune` are uploaded separately to their respective app rules.

The CMD launchers choose native 64-bit Windows PowerShell when the Intune process is 32-bit, and preserve its exit code. They require no downloaded runtime on endpoints.

## Configure the Win32 app

### Program

| Setting | Value |
| --- | --- |
| Name | Device name remediation |
| Install command | `Install.cmd` |
| Uninstall command | `Uninstall.cmd` |
| Install behavior | **System** |
| Device restart behavior | **No specific action** |
| Allow available uninstall | **No** |
| Installation time required | 5 minutes |

Configure these return codes deliberately:

| Code | Intune code type | Meaning in this package |
| --- | --- | --- |
| `0` | Success | Compliant by the time installation ran, or no reboot remains |
| `3010` | **Success** | Rename staged; the custom popup requests the restart |
| `1618` | Retry | User/name state changed after requirements; retry later |
| `1` | Failed | Rename, verification, or receipt write failed |

**Change the default 3010 mapping from Soft reboot to Success for the popup-only configuration.** This intentionally gives up Intune's built-in reboot-needed status for this app. If you prefer Intune to manage reboot notification, map 3010 to **Soft reboot** and choose **Determine behavior based on return codes**, then review your assignment restart settings. You may see both Intune's notification and this package's popup. Do not select a forced-restart option if the intention is only to ask the user to restart.

### Requirements

Set OS architecture to **64-bit/x64** and select a minimum Windows version supported in your environment. ARM64 and 32-bit Windows are not included in this pilot scope.

Add an additional requirement with these settings:

| Setting | Value |
| --- | --- |
| Requirement type | Script |
| Script | `Intune\Requirement-RenameComputer.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Run using logged-on credentials | **No** |
| Enforce signature check | No for this unsigned pilot; sign first if required by policy |
| Output data type | **Integer** |
| Operator | **Equals** |
| Value | **1** |

Do not configure the rule to compare an exit code. STDOUT `0` with exit code `0` is the deliberate normal not-applicable result.

### Detection

| Setting | Value |
| --- | --- |
| Rules format | Use a custom detection script |
| Script | `Intune\Detect-RenameComputer.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce signature check | No for the unsigned pilot; match your signing policy |

Detection emits a success string and exits `0` only when the receipt's target is still the configured computer name and the format is valid. If someone stages another rename, a stale receipt does not hide it. Without a matching receipt, detection exits `1` without STDOUT. All supplied PowerShell deployment scripts use UTF-8 with BOM.

### Assignment

Assign as **Required** to a small device pilot first. This depends on the intended console user's identity, so deploy after the user's first sign-in. Do not make it an Autopilot ESP blocking app: there may be no usable user during that phase.

Do not assign Uninstall to roll back a name. Uninstall removes only this package's receipt and reminder history, leaves its historical log, and leaves the active/pending computer name unchanged. Remove the Required assignment before any cleanup deployment. Detection still has reminder behavior whenever Intune evaluates it, including around cleanup; removing the assignment stops future app-driven evaluations.

## Quick changes to the original script

If first/last parsing has already been validated, this block enforces both length limits after computing `$userPCname`, `$chassis`, and `$randomString`:

```powershell
$userPCname = ($userPCname -replace '[^a-zA-Z0-9]', '').ToUpperInvariant()
if ($userPCname.Length -lt 2) { throw 'Unable to build a valid initial/surname prefix.' }
$suffix = '-{0}-{1}' -f $chassis.ToUpperInvariant(), $randomString.ToUpperInvariant()
$maxPrefixLength = [Math]::Min(9, 15 - $suffix.Length)
if ($maxPrefixLength -lt 2) { throw 'Device-type/random suffix is too long.' }
$userPCname = $userPCname.Substring(0, [Math]::Min($userPCname.Length, $maxPrefixLength))
$newPCname = $userPCname + $suffix
```

Additional findings in the original code:

| Original issue | Change in this bundle |
| --- | --- |
| `Rename-Computer` can emit a nonterminating error; catch alone does not guarantee handling | Use `-ErrorAction Stop`, `-PassThru`, `HasSucceeded`, and a registry post-check |
| Catch only logs, so an Intune command may still exit successfully | Explicit `exit 1` for actual failures |
| No definition of `Log` was included in the snippet | Add a concrete file logger that keeps requirement/detection STDOUT clean |
| Username split assumes two nonempty dot-separated components | Validate identity and defer unsupported formats |
| `Get-CurrentUser` already strips the domain; the second split and second call are redundant | Query the system once for eligibility; recheck immediately before changing it |
| Nine prefix characters can still exceed 15 with `SRV` | Compute the prefix budget from the complete suffix |
| Laptop list includes docking/expansion/peripheral enclosures | Remove codes 12, 18, 21; evaluate all returned chassis values before falling back |
| `DomainRole -ge 3` misses standalone servers | Include role 2 |
| Digits appear twice in the random alphabet | Use each A–Z/0–9 character once |
| Every run can generate a different target without pending-state checks | Recheck pending/compliant state inside the installer and avoid overwriting an existing pending rename |

There remains a small race between the final state check and `Rename-Computer`; Windows does not provide an atomic check-and-rename operation here. Avoid assigning competing rename scripts or policies.

## Local checks and troubleshooting

From an elevated Windows PowerShell terminal:

```powershell
# Preview only: no rename, receipt write, or popup. May append an audit log line.
.\Source\Install.cmd -AuditOnly

# Run the read-only/mocked logic tests in a separate process.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Test-NamingLogic.ps1

# Evaluate the actual requirement; CAN display the reboot reminder if pending.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Intune\Requirement-RenameComputer.ps1
```

For a true SYSTEM test, use the Win32 pilot or an approved SYSTEM execution tool. A successful administrator-session test alone does not prove the SYSTEM-to-user popup works.

Check:

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DeviceRenameRemediation.log
HKLM\SOFTWARE\DeviceRenameRemediation\Receipt
HKLM\SOFTWARE\DeviceRenameRemediation\Notifications
```

`Receipt` is a JSON registry value, and `Notifications` is a subkey with per-session JSON values. The log uses the existing Intune log directory; if that directory is absent, logging is skipped. Standard users should have no write access to the state key under HKLM. The installer treats failure to write its receipt as a failure; a staged rename still requires a restart even if receipt creation fails.

Pilot checks before broad rollout:

1. Already-compliant PC: no rename, no popup, requirement `0`/exit `0`, no receipt created by requirement.
2. Eligible PC with intended owner signed in: preview the target, install once, see the popup, and verify the two registry names differ.
3. Re-run while pending: no second rename and no extra popup within the throttle interval.
4. Restart: confirm the two names match and detection succeeds with the saved receipt.
5. Pre-existing pending rename made outside this package: see a popup while the requirement remains unmet, including a pending target that fails the naming pattern.
6. No user, unsupported username, AD domain join, or failed read: no rename. Check the logged reason.
7. Validate a locked console session and an RDP session, and check whether application-control policy permits the `Add-Type` interop used by the popup. A blocked popup must leave the rename block intact.

Validation completed: **94 checks passed in PowerShell 7.4.6 on Linux**, including native PowerShell syntax parsing and compilation of the C# session-messaging declarations. The bundled tests exercise name generation, requirement/detection outputs and exits, reminder throttling, error paths, and simulated before/after-restart behavior. They mock Windows registry/CIM/session APIs and `Rename-Computer`. They do not replace the Windows/SYSTEM/Intune pilot.

## Sources

- [Microsoft: add and assign a Win32 app](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32) — requirement output, detection output, return codes, restart settings.
- [Microsoft: prepare Win32 app content](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package) — packaging workflow.
- [Microsoft: Rename-Computer](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/rename-computer?view=powershell-5.1) — rename result and domain credentials.
- [Microsoft: Win32_ComputerSystem](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem) — console user and domain role.
- [Microsoft: Win32_SystemEnclosure](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure) — chassis values.
- [Microsoft: computer naming conventions](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou) — 15-character NetBIOS limit.
- [ComputerManagementDsc: pending reboot implementation](https://www.powershellgallery.com/packages/ComputerManagementDsc/10.0.0/Content/DSCResources%5CDSC_PendingReboot%5CDSC_PendingReboot.psm1) — active/configured name comparison.
- [Microsoft: WTSSendMessageW](https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtssendmessagew) — asynchronous session message API.
- [Microsoft: error handling](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_error_handling?view=powershell-5.1) — terminating errors and catch behavior.
