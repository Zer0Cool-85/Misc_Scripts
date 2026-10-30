# NinjaOne Windows Remediation Starter Pack

Version **1.0.0** · Prepared **October 30, 2026** · Windows x64 workstations · PowerShell 5.1+

Ten standalone scripts for an Intune-managed Windows fleet, with NinjaOne device status fields and optional repairs. Every script defaults to **Detect**. Run them as **SYSTEM** in NinjaOne with **64-bit** architecture. Each file includes everything it needs; there is no shared module to deploy.

Start with **disk space, Intune Management Extension, reboot readiness, and Fast Startup** on a small pilot policy. Review the other checks' assumptions before attaching repairs.

## 1. What is included

| # | Script/check | Detection | Available repair |
|---|---|---|---|
| 01 | Reboot readiness | CBS / Windows Update reboot signals; uptime of 14 days or more | Report only; connect your notification or an approved native reboot workflow |
| 02 | Disk space | OS drive below 15 GiB **or** 10% free | Delete eligible old, top-level Windows Temp files; check free space again |
| 03 | Intune Management Extension | Missing, disabled or non-running IME service | Start an installed, nondisabled service; preserve its startup type |
| 04 | Required services | Check your explicit service list; defaults to `CSFalconService` | Start existing, nondisabled services only with `-AllowServiceStart` |
| 05 | Firewall profiles | Effective Domain, Private and Public profiles enabled | Enable affected local profiles with `-AllowEnableFirewall`; verify effective policy |
| 06 | BitLocker OS drive | Fully encrypted OS volume and protection On | Resume eligible suspended protection with `-AllowResumeBitLocker` |
| 07 | Windows Time | Running service and reported synchronization state | Start a nondisabled service and resync with the existing configured sources |
| 08 | Fast Startup | Explicit local disabled setting; central require-on conflict | Set local `HiberbootEnabled=0` if no require-on policy is present |
| 09 | Windows image health | DISM Quick existing corruption flag or Full component-store scan | DISM RestoreHealth with `-AllowOnlineRepair`; maintenance window |
| 10 | Local Administrators | Direct membership compared with approved SIDs | Report only; resolve membership through your Intune account protection policy |

Files:

- `Scripts/`: the 10 complete PowerShell scripts.
- `Custom-Fields.csv`: exact field definitions for manual creation.
- `Automation-Plan.csv`: schedules, timeouts and ready-to-copy parameters.
- `QUICK-START.md`: condensed setup checklist.
- `Tests/Test-PackLogic.ps1`: parser checks and mock-based behavior tests.
- `VALIDATION.md`: what was tested and what requires a live pilot.

**The CSVs are configuration worksheets, not NinjaOne bulk-import files.** This package does not create fields, import automations or change your tenant by itself.

## 2. Create device custom fields first

In NinjaOne, open **Administration → Devices → Global Custom Fields** (some console layouts group this under **Device Custom Fields**), then **Add → Field**. Use **Device** definition scope only. Create the fields below, using the exact internal **Name**, not just the display label. Set **Automations / Scripts: Read/Write**, **Technicians: Read Only** or editable according to your policy. API access is not required. Leave fields optional, with no default status value. [NinjaOne field setup](https://www.ninjaone.com/docs/endpoint-management/custom-fields/)

| Check | Status field: Text | Details field: Multi-line |
|---|---|---|
| Reboot | `n1RebootStatus` | `n1RebootStatusDetails` |
| Disk | `n1DiskStatus` | `n1DiskStatusDetails` |
| Intune IME | `n1ImeStatus` | `n1ImeStatusDetails` |
| Required services | `n1ServicesStatus` | `n1ServicesStatusDetails` |
| Firewall | `n1FirewallStatus` | `n1FirewallStatusDetails` |
| BitLocker | `n1BitLockerStatus` | `n1BitLockerStatusDetails` |
| Windows Time | `n1TimeStatus` | `n1TimeStatusDetails` |
| Fast Startup | `n1FastStartupStatus` | `n1FastStartupStatusDetails` |
| Windows image | `n1ImageStatus` | `n1ImageStatusDetails` |
| Local administrators | `n1LocalAdminStatus` | `n1LocalAdminStatusDetails` |

The recommended setup is **20 fields**: ten exact-value status fields and ten timestamped details fields. To start with only ten status fields, add **`-StatusOnly` to every evaluation, scheduled and remediation invocation**. Details will still appear in script output. This removes the device details/timestamp fields, so reporting freshness is less convenient.

Role fields also work, but you must assign them to every targeted Windows device role. Global fields with Device-only scope are the simpler pilot setup. Avoid Organization or Location scope for these per-device results.

The scripts prefer the current `Set-NinjaProperty` command and fall back to `Ninja-Property-Set`. The agent supplies these commands. Field changes sync to the console asynchronously, typically within a few minutes. [Current command](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/command-line-interface-cli/powershell-set-ninjaproperty/) · [Legacy command](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/command-line-interface-cli/powershell-ninja-property-set/) · [Agent module](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/command-line-interface-cli/index-of-powershell-commands-and-articles/)

## 3. Understand status and exit codes

| Field value | Exit | Meaning |
|---|---:|---|
| `Healthy` | 0 | The selected checks passed during this run |
| `Remediated` | 0 | A repair was attempted and the subsequent check passed |
| `Issue` | 1 | A finding remains; includes report-only findings and repairs awaiting an explicit option |
| `Error` | 2 | Detection, execution or reporting could not complete reliably |
| `NotApplicable` | 0 | Windows Server was excluded by the workstation scope guard |

`Remediated` describes the latest run. A subsequent clean detection writes `Healthy`; the fields are snapshots, not a repair history database. A recent check time matters: an offline machine can retain an old Healthy result. Use NinjaOne last contact/online status and the details timestamp when assessing a device.

Example details value:

```text
Check: IntuneManagementExtension
Version: 1.0.0
State: Remediated
CheckedUtc: 2026-10-30T14:05:00Z
Mode: Remediate
Summary: Intune Management Extension service is running.
Before: Intune Management Extension is not in the expected running state.
Action: Started or waited for IME. The service was not restarted and its startup type was preserved.
After: Service=IntuneManagementExtension; State=Running; StartMode=Auto
```

Every completed run also prints `N1_RESULT=<state>` and a UTC timestamp. The details field is written before the final status. A field error returns exit 2 and attempts to mark the status Error; if NinjaOne rejects all writes, the old field values remain. A repair may already have completed before a reporting error. Review script output in that case. A timeout, parameter-binding failure or killed process can also leave stale fields.

## 4. Add the scripts to NinjaOne

1. Open **Administration → Library → Automation → Add / Add automation → New Script**.
2. Give it a name such as **N1 - Disk space** and a category such as **Windows Health**.
3. Select **PowerShell**, **Windows**, **64-bit**, and **SYSTEM** wherever run context is requested.
4. Paste the **entire** matching `.ps1` file or use the console's upload option if available.
5. Use ordinary PowerShell named parameters, such as `-Mode Detect -MinFreeGB 15`. The scripts do not require NinjaOne Script Variables or environment-variable mappings. Do not paste the `powershell.exe` command, filename, `$true`, or `&` into the parameters field.
6. Save, then run on one pilot device before scheduling.

NinjaOne supports preset parameter strings and accepts string arguments; these scripts convert validated numeric parameters through PowerShell. Boolean options are switches: use `-AllowServiceStart`, not `-AllowServiceStart $true`. [Automation Library](https://www.ninjaone.com/docs/administration/script-library/) · [Parameters](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/automation-parameters/) · [Scripting considerations](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/getting-started-automation-scripting/)

Keep source defaults at **Detect**. If an evaluation selector in your console does not expose the parameters you need, save a clearly named **detection-only copy** with the desired defaults in its `param()` block. For example, configure your approved admin SIDs in that detection copy. Use identical thresholds/service lists/allowlists in its repair action. Do not change the default mode of a script used for evaluation to Remediate.

## 5. Run a small pilot

1. Create or clone a Windows workstation policy named **N1 Remediation Pilot**, assigned to 3–5 test workstations. Include an Intune-managed machine and the security agents you expect.
2. Run **01, 02, 03 and 08** individually with `-Mode Detect` as SYSTEM. Confirm both custom fields populate and inspect the timestamp. No endpoint repair runs in Detect mode; field reporting still runs.
3. Validate a known noncompliant result safely: temporarily run Disk with a threshold above that test machine's free space, while remaining in Detect mode. Restore the normal threshold afterward. No need to disable firewall or encryption to test the framework.
4. Pilot a repair on a real, approved issue. Run the same script with `-Mode Remediate`. Confirm a successful repair writes `Remediated`, then another detection writes `Healthy`.
5. Confirm the expected behavior when an issue is not automatically repairable. For example, a missing IME remains `Issue`; it does not produce a false success.
6. Configure 04's required service list and 10's approved admin SIDs before interpreting fleet-wide results. For 05, 06 and 09, review the explicit repair options below.
7. Observe the pilot for several business days, then expand in rings. Use your existing Windows rollout groups where practical.

All scripts are designed for Windows 11 x64 workstation use. Windows 10 x64 may run them but was not tested here; evaluate supported/ESU estate separately. This package was validated with PowerShell parsing and mocks on Linux, **not** against your NinjaOne tenant or Windows modules.

## 6. Choose how to run them

### Option A: scheduled self-check and repair

This is the quickest starting point. Under **Administration → Policies → your policy → Scheduled Automations → Add automation**, choose a script, set SYSTEM and its parameters, then configure a schedule and save the policy. [Scheduled automations](https://www.ninjaone.com/docs/policies-and-conditions/policies/scheduled-automations-under-policy/)

Use `-Mode Detect` initially. Once approved, switch suitable checks to `-Mode Remediate`; each execution checks first, repairs only an Issue, then verifies. Use custom fields for searches. Exit 1 intentionally means an unresolved finding and can appear as an unsuccessful automation; interpret it through this pack's status contract.

### Option B: detection → condition → repair

This resembles Intune detection/remediation separation and is the recommended approach when you want alerts and controlled automatic response.

Example for **Intune Management Extension**:

| Setting | Value |
|---|---|
| Policy location | Administration → Policies → pilot policy → Conditions → Add condition |
| Condition type | Script Result |
| Evaluation script | N1 - Intune Management Extension |
| Evaluation parameters | `-Mode Detect` (also the script default) |
| Evaluation frequency | Every 4 hours |
| Timeout | 120 seconds, or next supported value above that |
| Result code | Equals `1` |
| With Output | **Contains** `N1_RESULT=Issue` |
| Attached automation | Same script, `-Mode Remediate`, SYSTEM |
| Reset | When no longer met, after the next clean evaluation / available short delay |
| Notifications | Start with a pilot technician channel or low-priority ticket |

The result-code and output criteria are ANDed; output matching is case-sensitive. Script Result evaluation runs as SYSTEM. Enable **Script Error Notification** so evaluation failures receive attention. The attached action should run only for **Issue**, not for a generic nonzero result. For explicit exit-2 monitoring, add an alert-only Script Result condition using exit `2` and Contains `N1_RESULT=Error`; this runs another evaluation, so stagger it. Also monitor action failures, not just evaluation failures. [Condition types](https://www.ninjaone.com/docs/policies-and-conditions/conditions/policy-condition-types-explained/)

Configure auto-reset **when no longer met**; avoid a short reset-after-time loop that repeatedly retries a persistent fault. Verify reset/retrigger behavior in your tenant. A repaired field can show Remediated before the condition clears at the next evaluation. Report-only checks should notify without a repair attachment. [Condition configuration](https://www.ninjaone.com/docs/policies-and-conditions/conditions/ninjaone-policies-condition-configuration/)

Do not schedule the same check separately at the same times as its Script Result evaluation. A per-check mutex blocks overlapping runs; an overlapping run emits Error without overwriting the active run's fields.

**Why Script Result for triggers and custom fields for querying?** NinjaOne's current condition-type documentation says Custom Fields conditions require Automation **Read Only**, while these scripts need field write permission. Keep the fields writable and use Script Result conditions for this implementation. Field-based device searches still work. Confirm with NinjaOne support if your tenant offers different condition eligibility. Normal scheduled Script Result evaluations may not create Activity entries; the details field provides the latest check record.

### Suggested schedules and parameters

These are starting recommendations, not platform-required schedules. Stagger checks and avoid full image scans during patch installation. Use separate, mutually exclusive invocation schedules for different configurations of the same check.

| # | Cadence | Detection parameters | Repair parameters after approval | Timeout suggestion |
|---|---|---|---|---|
| 01 | Every 4 hours | `-Mode Detect -MaxUptimeDays 14` | Report only | 2 minutes |
| 02 | Daily | `-Mode Detect` | `-Mode Remediate` | 5 minutes |
| 03 | Every 4 hours | `-Mode Detect` | `-Mode Remediate` | 2 minutes |
| 04 | Every 4 hours | `-Mode Detect -ServiceNamesCsv "CSFalconService"` | Same list, `-Mode Remediate -AllowServiceStart` | 15 minutes for up to 20 services; 2 for a small list |
| 05 | Daily | `-Mode Detect` | `-Mode Remediate -AllowEnableFirewall` | 2 minutes |
| 06 | Daily | `-Mode Detect` | On demand: `-Mode Remediate -AllowResumeBitLocker` | 2 minutes |
| 07 | Daily | `-Mode Detect` | `-Mode Remediate` | 3 minutes |
| 08 | Daily | `-Mode Detect` | `-Mode Remediate` | 2 minutes |
| 09 | Quick daily; Full monthly in maintenance | `-Mode Detect -ScanType Quick` or `-Mode Detect -ScanType Full` | On demand: `-Mode Remediate -ScanType Full -AllowOnlineRepair` | Quick: 5 minutes; Full/repair: up to 2 hours |
| 10 | Daily | `-Mode Detect -AllowedSidsCsv "YOUR-APPROVED-SID-1,YOUR-APPROVED-SID-2"` | Report only | 2 minutes |

The SID placeholders above must be replaced with real SIDs; omit the argument during the first inventory run. For Full scans/repairs, use a scheduled or on-demand automation that permits the required duration. If your tenant's timeout cap is shorter, do not attach the long operation to a short Script Result condition. Allow the OS servicing operation to finish before another run; a killed script is not proof that servicing has stopped.

## 7. Query results and build device groups

Open **Devices → More Filters → Custom Fields**. Select a field, an operator, and its exact value, then Apply. Add the status fields as table columns and save useful searches with **Save group**. [Custom-field search](https://www.ninjaone.com/docs/custom-fields/finding-devices-by-custom-field-values/) · [Search filters](https://www.ninjaone.com/docs/new-to-ninjaone/search-tools/devices-search-filters/)

| View | Filter definition |
|---|---|
| Low disk needing attention | `n1DiskStatus` **equals** `Issue` |
| IME needs investigation | **Any**: `n1ImeStatus` equals `Issue`; `n1ImeStatus` equals `Error` |
| Any baseline finding | **Any**: each of the 10 status fields equals `Issue` |
| Check/reporting failures | **Any**: each of the 10 status fields equals `Error` |
| Not yet evaluated | Relevant status field **does not exist**; separately include a blank-value filter if your tenant represents empty fields that way |
| Recently repaired snapshot | Relevant status field equals `Remediated`; inspect CheckedUtc |

Create separate views for Issue and Error if that is easier to operate. Do not filter only for “does not equal Healthy”: that also groups valid Remediated and NotApplicable values. Combine results with device last contact and open the details field to assess age. **Healthy does not prove that a scheduled check ran recently.**

For broader analysis, use **Export with custom fields** from Devices. NinjaOne documents that this export includes custom-field last-update data. The details fields also embed `CheckedUtc`. [Devices page and export](https://www.ninjaone.com/docs/new-to-ninjaone/search-tools/devices-search-page/)

## 8. Configure each check for your environment

### 01 — Reboot readiness

Default: uptime **>=14 days**, CBS RebootPending or Windows Update RebootRequired. `-IncludePendingFileRename` also treats pending file rename operations as a finding. Without that option the count is informational, because software can leave stale entries. The script does not claim to cover every reboot signal. A real Restart refreshes kernel uptime; shutdown with Fast Startup may not. Use NinjaOne's native reboot automation within your agreed user/maintenance process. [Microsoft pending-restart registry examples](https://learn.microsoft.com/en-us/industry/healthcare/powerscribe-one/client-installation-guide/dvd-image-install-upgrade) · [NinjaOne reboot guidance](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/getting-started-automation-scripting/)

### 02 — Disk space

Both thresholds must pass. PowerShell's `1GB` unit is 1 GiB (1,073,741,824 bytes). To customize:

```text
-Mode Remediate -MinFreeGB 20 -MinFreePercent 10 -TempAgeDays 14 -MaxDeleteMB 2048 -MaxDeleteFiles 2000
```

Cleanup is limited to files directly inside `%WINDIR%\Temp`, with both creation and modification older than the age threshold. It skips reparse points and directories, caps eligible deletion at 2 GiB / 2,000 files per run by default, and tolerates locked files. The action reports logical bytes removed and observed disk-free change separately. It leaves user folders, browser data, Recycle Bin, package caches and nested Temp directories alone. If space is still below either threshold, status stays Issue. Deleted temporary files have no rollback; use Detect mode to inventory before enabling cleanup.

### 03 — Intune Management Extension

This is a **service availability check**, not an Intune enrollment or check-in validator. Missing IME can be legitimate on devices outside the managed app/script scope; target this check only where IME is expected. A stopped, nondisabled IME can be started. Missing/disabled installation is reported for enrollment or policy investigation. Review `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` for application processing issues; a running service alone does not prove a successful check-in.

### 04 — Required services

Default is `CSFalconService` for your CrowdStrike estate. Confirm that internal service name on your endpoints. Discover names for the other agents locally:

```powershell
Get-Service | Where-Object DisplayName -Match 'CrowdStrike|Cisco|AWS|Intune' |
    Select-Object Name, DisplayName, Status
```

Copy actual **Name** values into one comma-separated string, for example `-ServiceNamesCsv "ServiceName1,ServiceName2"` after replacing those placeholders. Healthy means all listed services are running and nondisabled; cloud connectivity and product health are separate checks. Starting security services may be blocked by product self-protection. The script respects disabled startup types and does not stop, restart, reinstall or reconfigure a service. Give different configurations different field names if they must coexist, or one run will overwrite another's results.

### 05 — Firewall

Detection reads the effective `ActiveStore`. Repair writes profile Enabled=True to the local `PersistentStore`, then checks effective settings again. Central policy can continue to override the local setting; that leaves Issue. Enable automatic repair only after checking your intended Intune baseline and remote management access. This assesses profile enablement, not firewall rule correctness. [Get-NetFirewallProfile](https://learn.microsoft.com/en-us/powershell/module/netsecurity/get-netfirewallprofile?view=windowsserver2025-ps) · [Set-NetFirewallProfile](https://learn.microsoft.com/powershell/module/netsecurity/set-netfirewallprofile)

### 06 — BitLocker

Use daily Detect and **on-demand** resume by default. Protection can be suspended intentionally during BIOS/firmware work. Before passing `-AllowResumeBitLocker`, confirm that maintenance is complete and recovery keys are escrowed through your existing process. Resume is restricted to an unlocked, fully encrypted OS volume with protection Off. Encryption/decryption in progress, paused conversion and unencrypted volumes remain Issue. Recovery keys are never written to output or fields. Escrow, encryption method and data drives are outside this check. [BitLocker operations](https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/operations-guide?tabs=powershell) · [Resume-BitLocker](https://learn.microsoft.com/en-us/powershell/module/bitlocker/resume-bitlocker?view=windowsserver2025-ps)

### 07 — Windows Time

This baseline expects W32Time to be running. If your policy intentionally uses trigger-start with long stopped periods, adjust targeting before treating stopped as a fault. The script checks numeric leap indicator and stratum in the first two `w32tm /query /status` rows. Unexpected layouts produce Error. It does not independently measure offset or enforce maximum last-sync age. Repair requests `/resync /rediscover` using existing sources, preserving NTP/domain settings. Verify synchronization on representative language builds during pilot. [Windows Time tools](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)

### 08 — Fast Startup

The target is an explicit **local** disabled baseline, even if hibernation is currently unavailable. A missing local value is treated as Issue. Repair sets `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power\HiberbootEnabled` to DWORD 0. If the `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` policy requires Fast Startup, the script reports the conflict for policy correction. Disabling the “Require use of fast startup” policy itself only allows the local setting; it does not automatically turn Fast Startup off. [Microsoft policy mapping](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-wininit)

### 09 — Windows image health

Quick uses **CheckHealth**: it checks an existing corruption flag and is not a fresh scan. Full uses **ScanHealth**, which scans the component store. Approved repair uses **RestoreHealth** and may obtain files from configured sources / Windows Update. A failed download or servicing operation returns Error; non-repairable corruption remains Issue. This does not assess every protected system file or replace SFC diagnostics. Use a maintenance window and check `%WINDIR%\Logs\DISM\dism.log` for servicing details. [Repair-WindowsImage](https://learn.microsoft.com/en-us/powershell/module/dism/repair-windowsimage?view=windowsserver2025-ps)

### 10 — Local Administrators

First run with no allowlist to inventory direct members in the details field. The built-in local Administrator (RID 500) is allowed for group membership; every other member must be explicitly approved by SID. This does not validate that built-in account's disabled state or LAPS configuration. Add legitimate LAPS-managed accounts, Entra role/group SIDs and your approved support groups individually. Use the same allowlist in every invocation targeting that device class.

```powershell
Get-LocalGroupMember -SID 'S-1-5-32-544' |
    Select-Object Name, SID, PrincipalSource, ObjectClass
```

Membership is not expanded through nested groups or Entra role assignments; it is not an effective-access calculation. If orphaned/unresolvable members make `Get-LocalGroupMember` fail, the check returns Error instead of claiming compliance. Review membership through Intune Account protection / Local user group membership, accounting for your emergency support access. [Get-LocalGroupMember](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember?view=powershell-5.1)

## 9. Common options and troubleshooting

| Situation | Action |
|---|---|
| Field does not update | Verify internal Name, Device scope, role assignment if applicable, and Automation Read/Write. Allow agent sync time and inspect output. |
| No NinjaOne field command | Run through NinjaOne on an agent-managed device. For an elevated local test only, add `-SkipCustomFields`. |
| Script returns 1 / looks failed | Read `N1_RESULT` and summary. Exit 1 is an unresolved finding by design. |
| Condition never triggers | Match exit 1 **and** the exact case-sensitive token `N1_RESULT=Issue`. Confirm it is evaluating in Detect mode and field reporting is not failing with exit 2. |
| Status is Healthy but timestamp is old | Check agent last contact, policy assignment, schedule and script errors. Fields do not automatically expire. |
| 32-bit or local accounts error | Select 64-bit. Microsoft's LocalAccounts module is unavailable in 32-bit PowerShell on 64-bit Windows. |
| Already running | Remove overlapping schedules. Wait for the current run/servicing operation before retrying. |
| Remediate does nothing | Read Repair decision: a flag, missing service, disabled policy or report-only design may prevent repair. |
| No Activity entry for routine condition check | Expected for some Script Result evaluations. Inspect custom-field CheckedUtc and triggered-condition notifications. |

To use different names, supply both overrides everywhere the script runs:

```text
-Mode Detect -StatusField myImeStatus -DetailsField myImeDetails
```

For an elevated local pilot without field reporting:

```powershell
.\Scripts\N1-03-IntuneManagementExtension.ps1 -Mode Detect -SkipCustomFields
$LASTEXITCODE
```

Do not use `-SkipCustomFields` in production if you expect queryable device status. The scripts emit results to NinjaOne and the configured fields; there is no extra local log retention system. DISM and IME retain their own product logs.

## 10. Pause, rollback and maintenance

To pause changes, remove the repair attachments or switch scheduled runs back to Detect. Completed changes remain: service starts, firewall enablement, resumed encryption protection, a registry setting, file deletion or DISM repair. There is no universal undo. Restore an intended configuration through its owning policy; temporary-file deletion and servicing repairs are not transactionally reversible. Keep completed firmware maintenance separate from BitLocker resume automation.

Changing a script in NinjaOne's library affects automations that reference it. Version a pilot copy first, validate, then promote. Preserve your parameter strings and field names alongside the code. [Automation Library FAQ](https://www.ninjaone.com/docs/endpoint-management/scripting-and-automation/automation-library-faq/)

See **VALIDATION.md** before rollout. Source links were checked on October 30, 2026; console labels and tenant feature availability can vary.
