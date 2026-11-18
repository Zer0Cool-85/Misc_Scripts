# Claude Policy Manager for Intune

Version 1.0.1 · Windows PowerShell 5.1 · Documentation reviewed November 17, 2026

Deploy this as a **System-context Win32 app**. It manages the native 64-bit `HKLM\SOFTWARE\Policies\Claude` values, stores its configuration and engine in `%ProgramData%\ClaudePolicyManager`, and runs the SYSTEM task `\ClaudePolicyManager-Enforce`.

This package configures Claude Desktop; it does not install the Claude application. It includes a JSON entry for every one of the 12 currently documented enterprise policy values. See **POLICY-REFERENCE.md** for every setting's input format and behavior.

## What is included

| Item | Purpose |
|---|---|
| `Source\PolicyConfig.json` | Your deployment configuration; all 12 policy keys are listed |
| `Examples\All-Settings.example.json` | All 12 values populated to demonstrate their data types; placeholders must be replaced |
| `Examples\Config-1-ChatOnly.json` | A runnable example that blocks extensions, local MCP, Code, and Cowork |
| `Examples\Config-2-AllowCode.json` | Demonstrates enabling Code while retaining Config 1's other restrictions |
| `Source\Install.cmd` / `Uninstall.cmd` | Native 64-bit PowerShell launchers for Intune |
| `Source\Install-PolicyManager.ps1` | Fresh install or in-place update, with rollback on a caught failure |
| `Source\Enforce-Policies.ps1` / `PolicyEngine.psm1` | Protected enforcement engine and shared functions |
| `Source\Uninstall-PolicyManager.ps1` | Stops the task before registry cleanup and guards against stale-package uninstall |
| `Prepare-Package.ps1` | Validates config, creates the payload manifest and Intune detection script, and optionally invokes Microsoft's packaging tool |
| `Test-Configuration.ps1` | Validates and shows registry mappings without changing a device |
| `Tests` | Portable logic/transaction tests with simulated Windows services |

The shipping `Source\PolicyConfig.json` is intentionally unconfigured: change `ConfigurationId` from `CHANGE-ME` and set at least one policy or removal. Preparation rejects an unconfigured file. Example folders are outside `Source` and are not included in the Win32 payload.

## Prepare and package

1. Extract the ZIP to a working folder on your packaging PC.
2. Edit `Source\PolicyConfig.json`. Alternatively, copy one of the two pilot examples over it and customize that file.
3. Validate and prepare from PowerShell in the extracted folder:

   ```powershell
   .\Test-Configuration.ps1
   .\Prepare-Package.ps1
   ```

4. Prepare creates `Source\PackageManifest.json` and **Detect-Installation.ps1** in the bundle's root. Neither should be hand-edited. Run Prepare again after any config or source-engine change. If you sign the source scripts, sign them before preparation so the hashes match.
5. Package with the official [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool):

   ```powershell
   .\Prepare-Package.ps1 -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
   ```

   Or use the tool directly after preparation:

   ```powershell
   C:\Tools\IntuneWinAppUtil.exe -c .\Source -s Install.cmd -o .\Output -q
   ```

Upload the resulting `.intunewin`. This ZIP contains the source bundle, not a preconfigured `.intunewin`.

## Intune app settings

| Field | Value |
|---|---|
| App type | Windows app (Win32) |
| Install command | `Install.cmd` |
| Uninstall command | `Uninstall.cmd` |
| Install behavior | **System** |
| Device restart behavior | No specific action |
| Requirements | Your supported 64-bit Windows 10/11 estate; native Windows PowerShell 5.1 |
| Detection | Use the generated **Detect-Installation.ps1**, uploaded as a custom detection script |
| Run detection as 32-bit process on 64-bit clients | **No** |
| Enforce detection signature check | No for the supplied unsigned script; follow your signing process if enabling it |
| Return codes | `0` success; `1` failure |
| Assignment | Required, initially to a pilot device group |

Detection checks the assigned package's exact manifest hash, payload/config hashes, protected file permissions, task definition and permissions, registry audit prerequisites when enabled, and effective registry values. A failed check returns not detected so a Required assignment can repair at an Intune evaluation/retry; this is not an immediate or continuous Intune watchdog.

The runtime scripts require SYSTEM, including local testing. An ordinary elevated administrator console is not the same context. Preparation and configuration validation do not require SYSTEM and do not apply policies.

Remove competing management of these same Claude values before the pilot: an old profile, platform script, GPO, or other agent could continually overwrite this manager. This package needs no Intune Remediations license.

## Configuration and ownership

| JSON instruction | Fresh installation | Later installation/update |
|---|---|---|
| Non-null value in `Policies` | Enforce that value and type | Replace the old instruction for that policy |
| `null` or omitted policy | Do not start managing it | **Retain its previous enforced instruction**, if this manager already owned it |
| Policy name in `RemovePolicies` | Enforce absence of that value | Replace the prior instruction with enforced absence |

This retention rule is deliberate: moving to a partial config does not silently release existing protections. To return a policy to Claude's unconfigured/default behavior, include its exact name in `RemovePolicies`. Its `Policies` entry must be null or omitted. The task will keep that registry value absent. To enforce a value again, remove the name from `RemovePolicies` and provide its new value.

Example removal fragment:

```json
"Policies": {
  "forceLoginOrgUUID": null,
  "isLocalDevMcpEnabled": false
},
"RemovePolicies": ["forceLoginOrgUUID"]
```

Do not put JSON comments, PowerShell expressions, commands, or arbitrary registry paths in the configuration. Only the known policy names are accepted. UUIDs, booleans, hours, effort choices, and path formats are validated. The engine cannot verify organization membership, EDR vendor support, or whether a path is the right business location.

`ConfigurationId` identifies the assignment (for example, `Finance-ChatOnly-003`). It is not an organization UUID. Only one configuration package should be assigned to a device at a time.

## Scheduled task and registry events

| Enforcement property | Meaning |
|---|---|
| `IntervalMinutes` | Integer 1–1440; examples use 15; repeats indefinitely |
| `RunAtStartup` | Start approximately 30 seconds after boot |
| `RunAtLogon` | Start approximately 30 seconds after any user signs in |
| `RunOnRegistryChange` | Subscribe to Security events 4657 and 4663 for the Claude policy key; approximately 5-second trigger delay |
| `ConfigureAuditPolicy` | During installation, enable machine-wide **Audit Registry / Success**; only valid when the event trigger is enabled |

The example configurations enable all triggers and automatic audit setup. If your security baseline manages auditing, set `ConfigureAuditPolicy` to false and ensure Audit Registry success auditing is already enabled; installation verifies it. Setting `RunOnRegistryChange` to false and `ConfigureAuditPolicy` to false uses only startup/sign-in/periodic enforcement.

An event trigger is not a direct registry callback. Windows must produce the audit event. The installer adds a **Success** SACL for **Set Value** and **Delete** on the Claude key only, preserving existing audit entries. Event 4657 covers registry value creation, modification, and deletion; 4663 provides additional audited object-access/delete coverage. The periodic trigger remains necessary for missing keys, audit-log gaps, disabled auditing, or changes that do not produce the subscribed event. Verify actual event coverage in the pilot.

Enabling Audit Registry success auditing is machine-wide and may activate auditing on other keys that already have SACLs. On uninstall, the manager restores its previous key SACL only if that SACL still matches its last managed form; otherwise it leaves externally changed auditing intact. It **does not disable the shared machine-wide audit setting**. Review that setting separately if you no longer need it.

The task runs as SYSTEM with the highest run level, works on battery, does not require a network, and avoids overlapping instances. Missing starts may run when Windows becomes available again. It does not wake a sleeping PC. A no-op run reads the registry but does not rewrite correct values, avoiding a sustained event loop.

## Moving from config 1 to config 2

Install config 2 over the existing manager. Do not uninstall config 1 first.

| Phase | Behavior |
|---|---|
| Validate | Validate the incoming config and payload before changing the installed manager |
| Acquire | Acquire the shared operation lock, then disable/stop the task |
| Preserve | Snapshot current managed registry values, installed files/state, audit SACL, and task definition |
| Apply | Keep existing policy values in place; write replacements/additions before explicit removals |
| Verify | Register the new task and verify the installed state |
| Recover | On a caught error, restore previous values, files/state, audit SACL, and task definition |

There is no uninstall-and-reinstall clearing of the policy key. Individual registry writes are not one atomic Windows registry transaction, so this is a staged update with rollback, not a promise against power loss during installation. A subsequent Required-app evaluation can repair an interrupted deployment.

For the supplied examples, config 1 blocks Code/MCP/extensions/Cowork. Config 2 enables Code and sets its effort while continuing to enforce config 1's other restrictions. A fresh config 2 installation manages only its two specified values; add the rest of your baseline if it must also stand alone.

The simplest rollout is to update the **same Intune Win32 app** with the new content and its newly generated detection script. For separate apps, use supersedence with **Uninstall previous version = No**, and move assignment scope so only the intended configuration is Required. Simultaneously requiring A and B causes competing package ownership; this bundle cannot decide which Intune assignment is authoritative.

The uninstall script compares the calling package's manifest with the installed manifest **while holding the lock**. A delayed uninstall from config 1 skips a device already updated to config 2. That guard does not make it safe to schedule an old uninstall before the new install.

## Uninstall modes

| Command | Result |
|---|---|
| `Uninstall.cmd` | Default: restore values that existed before this manager first took ownership; remove values originally absent |
| `Uninstall.cmd -Mode RemoveManaged` | Remove the manager's tracked policy values |
| `Uninstall.cmd -Mode KeepPolicies` | Remove the task/engine but leave registry policy values in place |

Uninstall disables and stops the task under the operation lock before changing the registry. It then removes the task registration before deleting the local manager folder. A failed cleanup of policy values restores the pre-uninstall state and task where possible. The global Audit Registry setting is left alone as described above.

Restore/remove operations only touch values that still match the manager's last enforced state. Values changed by another owner are left intact. The whole Claude registry key is never recursively deleted. Other Claude settings and the Claude app are not uninstalled.

For an Intune removal deployment, stop requiring the manager and use the matching current package's Uninstall assignment. Manually uninstalling while the app remains Required lets Intune reinstall it.

## Protection, logs, and pilot checks

The local manager directory and its files allow SYSTEM and local Administrators full control; standard users have no access. The task is also restricted to SYSTEM/Administrators. Reparse-point destinations are rejected. Registry values use the ordinary HKLM policy permissions so Claude can read them.

This protects against standard-user changes. It is not tamper protection against a local administrator, who can take ownership, stop/delete tasks, change audit settings, or alter files. The scheduled task can restore registry drift while it is running normally; altered/deleted engine/config files require Intune repair. No local scheduled task can guarantee continuous enforcement against an administrator.

Inspect as SYSTEM or an elevated administrator:

```powershell
reg.exe query "HKLM\SOFTWARE\Policies\Claude" /reg:64
Get-ScheduledTask -TaskName 'ClaudePolicyManager-Enforce'
Get-ScheduledTaskInfo -TaskName 'ClaudePolicyManager-Enforce'
Get-Content "$env:ProgramData\ClaudePolicyManager\Status.json"
Get-Content "$env:ProgramData\ClaudePolicyManager\PolicyManager.log" -Tail 40
```

Logs rotate at approximately 2 MiB, retaining three older files. `State.json` contains the original snapshots and effective managed policy set; retain it if you need to recover original settings. Logs and backups are removed with the manager on a normal uninstall.

Pilot before broad deployment:

1. Deploy config 1 and check native registry types, task identity/triggers, directory ACLs, task result, and actual Claude behavior.
2. As a standard user, verify the config/scripts/task cannot be edited. In an authorized admin test, change/delete one managed value and verify its audit event and restoration. Also test the periodic fallback and whole-key deletion on the test device.
3. Fully quit and reopen Claude Desktop when validating policy behavior. The manager does not forcibly close the app or reboot Windows; registry restoration does not prove an already-running app has reloaded a setting.
4. Install config 2 without uninstalling config 1. Verify the new values and retained restrictions.
5. Invoke config 1's uninstall after config 2; verify it skips the current manager. Then test the matching config 2 uninstall and chosen cleanup mode.
6. Verify the new detection script in Intune, including a missing/disabled task repair scenario.

Portable tests passed for validation, registry drift logic, config transitions, and simulated install/update/rollback/uninstall transactions. **Actual Windows registry APIs, ACLs, Security auditing, Task Scheduler COM, and Intune delivery have not been exercised here.** See VALIDATION.md for the exact scope.

## Sources

- [Anthropic: Desktop enterprise policy reference](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop)
- [Microsoft: Win32 app deployment and custom detection](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Microsoft: registry value audit event 4657](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4657)
- [Microsoft: Audit Registry](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/audit-registry)
- [Microsoft: task security](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)
- [Microsoft: indefinite repetition](https://learn.microsoft.com/en-us/windows/win32/taskschd/repetitionpattern-duration)

## 1.0.1 diagnostic update (November 18, 2026)

This update adds diagnostics; it does not claim to resolve an as-yet unidentified Windows installation failure. Existing policy/update/uninstall behavior is unchanged.

1. Copy your customized `PolicyConfig.json` into the new `Source` folder. Do not reuse the old engine, manifest, or detection script.
2. Run `Prepare-Package.ps1` after the final edits, build a fresh `.intunewin`, and replace the app content and custom detection script in Intune together.
3. Use `Install.cmd` and `Uninstall.cmd`, with install behavior **System**. Do not bypass these wrappers: they capture output before PowerShell or the policy module can fail. Keep detection in native 64-bit mode.
4. Retry on the pilot device. No uninstall or deletion of existing policy folders is required for this update.

The wrappers append startup, execution identity, PowerShell executable, installation stage, detailed error record, script position, script stack, and exit code to:

- `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\ClaudePolicyManager-Install.log`
- `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\ClaudePolicyManager-Uninstall.log`

Detection failures are written to `ClaudePolicyManager-Detection.log` in the same folder (2 MiB plus one rotated copy). Missing-installation messages before installation are expected. Compare timestamps with the installer log. Detection still exits 1 without stdout on failure, and exits 0 with stdout on success.

If the IME log directory does not exist, the wrappers and detection use `%SystemRoot%\Logs` instead. If the wrapper cannot write its log, it continues with console output and preserves the installer exit code. Direct `.ps1` execution emits diagnostics to the console but is not automatically redirected to a file.

The regular runtime log remains `%ProgramData%\ClaudePolicyManager\PolicyManager.log`. Bootstrap logs are outside the protected manager folder, so they survive rollback/uninstall and capture failures before that folder exists. No configuration contents are deliberately dumped; error text can still contain a configured value or path, so review logs before sharing.

If neither the new installer log nor its fallback exists, verify the updated package was downloaded, Intune invoked `Install.cmd`, and application-control policy did not block cmd/PowerShell. Absence of the regular manager log alone does not identify the failure.
