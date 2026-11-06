# Enterprise first-logon setup · hotfix 10

Use [the ten-step profile](../Config/Enterprise-FirstLogon.json) on **new enrollments**. It removes Office before licensed users install it from Company Portal, cleans the detected OEM's catalog entries, names the PC, prepares Google apps, checks encryption, patches applications, and requires a restart. The existing five-step example, default demo and Store-app pilot retain their previous configurations.

**Start with [the inventory pilot](../Config/Enterprise-Inventory-Pilot.json).** It runs real detection and writes logs, without uninstalling, renaming, installing, changing encryption or restarting. It is useful on a representative Dell, Lenovo and HP before broadening the OEM list.

## Run it

1. Extract hotfix 10 alongside hotfix 9. Keep your branding, custom scripts, approved payloads and existing x64 `Tools/ServiceUI.exe`. Use a local package folder writable only by SYSTEM/Administrators; allow the signed-in user read/execute as in the previous release.
2. For a visual preview, run `Run-FirstLogon-Demo.cmd`. On Done, the required-restart notice is simulated. **Demo never installs, removes, renames or reboots.**
3. From your existing SYSTEM + ServiceUI desktop trigger, run `Run-Inventory-Live-ServiceUI.cmd`. Read `SetupUI.log`, `oem-Inventory.json` and `bitlocker-BitLocker.json`. Edit the name template in both profiles and the shared OEM catalog.
4. Stage the prerequisites below and run the preflight. On a disposable first-enrollment test PC, use `Run-FirstLogon-Live-ServiceUI.cmd` from that same SYSTEM trigger. **This profile really removes software and schedules a forced reboot.**
5. Deploy only during first provisioning. Assign Office as **Available** in Company Portal to your licensed group. Remove overlapping Required Office deployments during this window. A local cleanup script cannot control tenant licensing or prevent a separate deployment from reinstalling a product.

```powershell
# Fresh x64 Windows PowerShell 5.1, from the package root:
.\Start-DeviceSetup.ps1 -ValidateOnly -ConfigPath .\Config\Enterprise-FirstLogon.json
.\EnterpriseSteps\Test-EnterpriseConfiguration.ps1 -ConfigPath .\Config\Enterprise-FirstLogon.json
.\Tests\Invoke-ProvisioningTests.ps1
.\Tests\Invoke-EnterpriseWorkflowMocks.ps1
```

`-ValidateOnly` checks config structure; the enterprise preflight also checks the payload paths you list. Placeholder payloads fail that second check until replaced. Neither command executes a provisioning step. Use the existing `Tests/Invoke-SmokeTests.ps1`, `Invoke-WinGetFallbackTests.ps1` and `Invoke-LogAccessTests.ps1` for the earlier behaviors.

## The ten slots

| # | Step ID | Full-profile behavior |
|---|---|---|
| 1 | cleanup | All desktop Office versions detected, Store Office apps, and the separately configured OneDrive removal |
| 2 | oem | Manufacturer-specific cleanup using an exact list; incomplete matches produce a warning and IT detail |
| 3 | name | Stage the configured name; leave the actual restart to the controller |
| 4 | google | Install missing Chrome Stable and Drive for desktop machine-wide; check each app with Google Updater |
| 5 | portal_check | Check Company Portal for the signed-in user and record the HKLM flag |
| 6 | portal_install | WinGet first, staged offline fallback, then verify target-user registration |
| 7 | notepad | Same online/offline and verification behavior for modern Notepad |
| 8 | bitlocker | Read-only OS-volume audit; optionally enforce protection |
| 9 | updates | WinGet maintenance; incomplete or unavailable scans display **Skipped** |
| 10 | restart | Mark the final restart required; the controller schedules it after saving results |

The generic MSI installer is still included. To fit it in this profile, remove `portal_check` and clear `portal_install.DependsOn` before adding the MSI step. The Portal installer performs its own detection and registry update. Keep `restart` last. The ten-slot limit includes disabled entries.

## Office: remove once, then respect the licensed install

Set `OfficeRemovalMode` to `AllOffice` in `Step-RemovePreinstalledOfficeOneDrive.ps1`'s JSON parameters. Old configurations without that mode retain `SelectedProducts` and their existing allowlist. In AllOffice mode:

- With detected Click-to-Run products and a staged Microsoft-signed Office Deployment Tool, setup runs ODT with `<Remove All="TRUE"/>`. This includes products and languages such as **Visio and Project**. Business editions are intentionally in scope.
- For detected older MSI Office or remaining desktop evidence, it runs Microsoft's signed `GetHelpCmd.exe -S OfficeScrubScenario -AcceptEula -OfficeVersion All`. The Get Help route can also handle detected desktop Office without ODT. Stage the **entire extracted Get Help kit**, not just its EXE, at `Payloads/GetHelp/`. Microsoft limits each Get Help build's lifetime; refresh it on the packaging workstation. Stage the current extracted ODT `setup.exe` at `Payloads/ODT/setup.exe` for the normal Click-to-Run route.
- The script inspects both machine uninstall views, Click-to-Run registrations and standard Office executable locations. It removes known Store packages, including Office Desktop, the Microsoft 365 hub, Store OneNote and new Outlook, from provisioning and existing registrations. It verifies remaining evidence. Unrecognized portable copies, browser shortcuts, arbitrary per-user desktop installs and obsolete products outside Microsoft's tool coverage are not guaranteed to be removed. Known residuals fail the step for review; no arbitrary uninstall string is executed.
- `ForceCloseApps` defaults to false. Close open Office apps before retry. `RemoveOneDrive` is independent: the profile sets it to true; set false if you want to retain OneDrive. OneDrive removal retains the existing machine and interactive-user scope.
- After verification, the script records DWORD `AllDesktopOfficeRemoved=1` under `HKLM:\SOFTWARE\PostEnrollmentSetupUI\OfficeBaseline`. It honors this receipt on future runs, including after `-ResetState`, so a later licensed Portal install survives. A failed cleanup writes no receipt. **A device upgraded from hotfix 9 has no such receipt:** scope the new profile to fresh provisioning, not as a fleet-wide retrofit. The receipt is not entitlement enforcement and does not replace Intune detection.

To inventory before changing anything, set `AuditOnly: true` and `OfficeRemovalMode: "AllOffice"`. Running the pilot does not create the receipt. The primary log records matches; the full route adds ODT configuration or Get Help stdout/stderr in the run folder.

## Dell, Lenovo and HP cleanup

`Step-RemoveOemApps.ps1` reads `Win32_ComputerSystem.Manufacturer` and uses only that vendor's entry in [OemCleanup.json](../Catalogs/OemCleanup.json). Unknown manufacturers are a no-op. Set `Mode` to `Audit` or `Remove`. The report includes matched targets and additional vendor inventory to help refine the catalog.

| Vendor | Examples in the starter list | Kept by the starter list |
|---|---|---|
| Dell | Customer Connect, Digital Delivery, MyDell | Command Update, drivers, BIOS tools and SupportAssist |
| Lenovo | Lenovo Welcome and Lenovo Now | Commercial Vantage, System Update and hotkey utilities |
| HP | JumpStart, registration and QuickDrop | Image Assistant, diagnostics, hotkeys and security tools |

Edit exact AppX identities, desktop display names and trusted publisher names. No manufacturer-wide wildcard removal occurs. Review Digital Delivery before removal if you use it for purchased software. AppX removal covers both provisioned and registered instances. Recognized machine MSI entries use product-code uninstalls with logs and verification. EXE entries require a quoted quiet uninstall command, a supported silent switch, a vendor-signed uninstaller under Program Files, and a recognized executable name. Unrecognized commands remain installed and are logged for packaging; setup never guesses EXE switches. If any catalog match fails, the full example treats it as an optional warning, not a silent success.

## Device naming

Set the `name` step's `Parameters`; the supplied `PC` prefix is an example, not an assumed company standard.

```json
{
  "NameTemplate": "{Prefix}-{Type}{Serial:7}",
  "Prefix": "AC",
  "Site": "CLE",
  "LaptopCode": "L",
  "DesktopCode": "D",
  "PreviewOnly": false
}
```

For a laptop with serial `PF-1A2B3C4D`, this produces **AC-LA2B3C4D**. Other examples: `{Site}-{Serial:7}` or `{Prefix}-{Hash:8}`. Supported tokens are `Prefix`, `Site`, `Type`, `Serial`, `Asset` and `Hash`, written in braces. `Serial:N` and `Asset:N` use the rightmost N normalized characters; `Hash:N` uses the first N hex characters of SHA-256 of the SMBIOS UUID (default eight). Include at least one device-specific token. Hardware placeholders, invalid characters, reserved/all-numeric names and names longer than 15 characters are rejected. The script never truncates the completed name to hide a collision.

Preview first: a short serial tail or hash is **not** a tenant-wide uniqueness check. Select a convention that is unique in your inventory. The script checks the active and pending Windows names, skips an exact match and will not overwrite a conflicting pending rename. A real change calls `Rename-Computer` without an immediate restart and verifies the pending name. Designed for Entra-only/workgroup endpoints; it does not rename AD-domain PCs, edit Entra/Intune records, or change Autopilot profile settings. Avoid two competing naming owners.

## Google: install and verify the update offer

`Step-GoogleWorkspaceApps.ps1` takes `Apps: ["Chrome", "Drive"]`, or either one alone. It targets native x64 Windows. Missing machine installations use the evergreen Google-hosted enterprise Chrome MSI and Drive EXE; each installer must have a valid Google signature. Chrome installs quietly with no restart. Drive installs silently without starting the user's sign-in flow. Optional `ChromeMsiRelativePath` and `DriveExeRelativePath` use your staged copies; a live update check is still required. Existing installations go directly to that check.

For **each** selected app, the script checks its machine Google Updater registration, asks Google Updater (the machine COM interface) for an update, applies an offer, then checks again. It requires an explicit *no update offered* result, a signed installed binary, and a matching registered version. Successful cards show the final versions. An unavailable updater, network/policy error, version mismatch or still-available update is logged and fails the step. `UpdateTimeoutSeconds` defaults to 600 per app. Allow additional UI time for installer downloads.

“Current” means **the version Google offers that device under its channel, rollout and enterprise policy**. This does not override a version pin, prove every region has received a just-published build, switch a channel, sign anyone into Google, or replace ongoing Google updates. Include the Google Update path through your SYSTEM proxy in the pilot. Check policy and Google Updater logs on a failed offer; do not weaken signature checking.

## WinGet: machine and user scope, without a red failure

The update step checks existing applications; it does not install an inventory of missing applications.

- **Machine:** SYSTEM uses Microsoft's `Microsoft.WinGet.Client` module to enumerate updates from `MachineSource` (default `winget`) and apply them individually with `-Scope System -Mode Silent`. Failures on one app do not stop the other candidates. `ExcludeMachineIds` skips products with a different servicing owner; Chrome and Drive are excluded in the example. Set `RunMachineUpdates` false to omit this scope.
- **Signed-in user:** the existing limited-user task runs `winget upgrade --all --scope user --silent` with noninteractive agreement/authentication options against the user's configured sources. It does not pass `--force`, `--include-unknown`, `--include-pinned` or `--allow-reboot`. The primary log links this attempt to the user's WinGet logs. The machine exclusion list does not change user pins. Set `RunUserUpdates` false to omit this scope.
- **Stage the machine module once** from a packaging workstation with PowerShellGet and your approved PSGallery access: `.\Tools\Stage-WinGetClient.ps1`. Pass `-Version <approved-version>` to pin the staging operation. Include the resulting `Payloads/Modules` folder in your Intune package. An existing reviewed AllUsers installation under Program Files also works. Nothing downloads or installs a PowerShell module at first logon. The machine interface also needs a working Windows Package Manager service/API on the device. A missing module or blocked WinGet is a skip, not a bootstrap attempt.
- Set `Required: false` and `NonBlockingSkipExitCodes: [20001]` on this step. If an enabled scope is unavailable, times out or only partly completes, the card says **Skipped**, the run can still succeed, and IT gets the reason in `SetupUI.log`. Successful updates are retained. A scan with no applicable updates is a normal completion. The neutral skip is remembered on resume for the same step fingerprint and is never treated as a successful dependency. Leave other steps independent of it.
- The sample allows 900 seconds for the machine worker, 300 for user WinGet, and 1,800 total. Keep the UI timeout above both time budgets and task overhead. Ordinary maintenance failures are handled inside those budgets; an actual controller crash, lost completion state or outer worker timeout is still a setup fault. A timed-out client is not proof that servicing activity stopped.

There is no promise that every installed program maps to a WinGet package or supports a silent upgrade. Programs outside WinGet, unavailable manifests, blocked sources and apps requiring different permissions remain for your normal patching tool.

## BitLocker and one additional enterprise check

`Step-CheckBitLocker.ps1` checks **the Windows volume**, not every attached drive. `Mode: "Audit"` reports volume status, protection status, method and encryption percentage in the card/log and writes `<step-id>-BitLocker.json`. It does not change encryption or read recovery passwords into the report. To make this a gate, change both `Mode` to `RequireProtected` and the step's `Required` to true. Fully encrypted with protection On passes; suspended protection does not. `AllowEncryptionInProgress: true` also accepts actively encrypting **with protection On**. Local encryption is not proof of recovery-key escrow; verify escrow centrally in Intune/Entra.

A useful optional replacement for one slot is `EnterpriseSteps/Step-CheckRequiredServices.ps1`. For example, `{"ServiceNames":["CSFalconService"],"WaitSeconds":60}` checks that the CrowdStrike service is running if Falcon is required on that device. Add your actual agent service names as needed. It does not start services or substitute for sensor check-in or policy status in your security console.

## Required restart and result handling

The full profile supplies this policy and the final required `Step-RequireRestart.ps1`:

```json
"EnforceFinalRestart": true,
"RestartCountdownSeconds": 120
```

The final worker returns a reboot request; it **never reboots its own host**. After required work succeeds, the controller saves the run result, then schedules `shutdown.exe /r /f /t <seconds>`. A warning on a non-required step or a neutral WinGet skip does not block it. A required failure, controller fault, unsafe outer timeout, demo, or validation run does not schedule a restart. The live profile requires SYSTEM, persistent completion state, a reliable boot time and the last required restart card. Old profiles default to reminder/3010 only.

The countdown starts **at completion**, not when the user eventually clicks Done. Done, the title-bar X and Alt+F4 show the same acknowledgment notice. No Later or Cancel choice postpones Windows. Leaving the notice open or closing the WPF process does not cancel the OS schedule. Windows forces running apps closed at the deadline; tell users to save work. Choose 30–900 seconds. This controls the setup UI, not the actions of a local administrator. Coordinate with any deployment owner that also restarts on exit 3010.

A protected receipt records the boot identifier and deadline. A relaunch in the same boot does not extend a recorded countdown. Matching completed work after a new boot exits without another restart. If Windows rejects the schedule, the UI reports the error and offers **Retry restart**; no successful restart is claimed. For a fresh lab run use a VM snapshot or a clean enrollment. Do not clear production Office receipts or completion state as routine troubleshooting.

## Upgrade and pilot checklist

From hotfix 9, deploy the new `Start-DeviceSetup.ps1`, `Core/Setup.Common.ps1`, `Core/Invoke-SetupStep.ps1`, `UI/MainWindow.xaml` and `UI/StepViewModel.cs` together, plus the updated `EnterpriseSteps/`, new `Catalogs/` and your selected profiles. Add the staging helper, launchers, docs and tests as needed. Keep custom scripts, payloads, branding, `Tools/ServiceUI.exe` and production state. If you edited shipped files, merge rather than overwrite them. Existing JSON does not enable mandatory reboot or broad removal by itself. The changed Office script will be reconsidered by fingerprint on an older deployment, so pilot even when retaining its selected-product policy.

| Pilot on a disposable PC | Expected result |
|---|---|
| Inventory first | Correct manufacturer, exact matched app names, intended proposed name, no machine changes |
| C2R Microsoft 365 plus Project/Visio; separate legacy MSI image | Desktop and Store Office evidence gone; verify a subsequent licensed Portal install survives a rerun |
| Dell Command Update installed; unknown manufacturer | Command Update remains; unknown vendor makes no changes |
| Rename already active / pending same / pending different | No-op / report reboot needed / stop before overwriting another rename |
| BitLocker fully protected, suspended, encrypting | Audit exposes each actual state; strict mode honors the configured in-progress exception |
| Chrome or Drive missing, old, already current, blocked by policy/proxy | Install if needed, then app-specific update offer checked; blocked or inconclusive checks do not turn green |
| WinGet blocked, module missing, one installer fails, no applicable updates | Neutral skip with IT logs for incomplete work; success when a scan completes with nothing to do |
| Required step fails | Retry/support path; no mandatory restart until resolved |
| Successful live run: click Done / leave window open / relaunch after boot | Notice and forced OS restart / same deadline / no restart loop |
| Demo, including Done | Preview notice only; Windows stays up |

Build validation is documented in `Docs/STATIC-VALIDATION.txt`. The mocked PowerShell suites are supplied for Windows. Real NTFS, OEM uninstallers, Google COM/installer behavior, AppX, WinGet, BitLocker, rename, ServiceUI and shutdown must be piloted under your actual policy set.

## Primary references

- [Microsoft: ODT Remove All, including Project and Visio](https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options#remove-element)
- [Microsoft: command-line Get Help Office uninstall](https://learn.microsoft.com/en-us/troubleshoot/microsoft-365/admin/miscellaneous/get-help-office-uninstall) and [kit lifetime](https://learn.microsoft.com/en-us/troubleshoot/microsoft-365/admin/miscellaneous/get-help-command-line-overview)
- [Microsoft: computer naming rules](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou) and [Rename-Computer](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/rename-computer?view=powershell-5.1)
- [Google: Chrome enterprise deployment](https://support.google.com/chrome/a/answer/7650247) and [Drive for desktop deployment](https://knowledge.workspace.google.com/admin/drive/set-up-drive-for-desktop-for-your-organization)
- [Chromium: Windows updater COM implementation](https://chromium.googlesource.com/chromium/src/+/main/chrome/updater/app/server/win/com_classes_legacy.cc) and [updater state definitions](https://chromium.googlesource.com/chromium/src/+/main/chrome/updater/app/server/win/updater_legacy_idl.template)
- [Microsoft: WinGet SYSTEM support](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting#system-context), [upgrade options](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade), and [Update-WinGetPackage](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Help/Microsoft.WinGet.Client/Update-WinGetPackage.md)
- [Microsoft: BitLocker operations](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/operations-guide) and [shutdown timing/forced application close](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown)
