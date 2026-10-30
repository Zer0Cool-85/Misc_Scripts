# Quick start

1. **Unzip this folder.** Start with `README.md`; use this page as your checklist.
2. **Create a small Windows pilot policy.** Assign 3–5 test PCs.
3. **Create fields using `Custom-Fields.csv`.** Each check has a Text status field and a Multi-line details field. Use exact Names, Device-only scope, Automation Read/Write. These are reference definitions, not a CSV import template.
4. **Add each complete script** through Administration → Library → Automation → New Script. Choose PowerShell, Windows, 64-bit and SYSTEM. No helper module is needed.
5. **Run Detect first.** Example parameters: `-Mode Detect`. Begin with 01 Reboot, 02 Disk, 03 IME and 08 Fast Startup. Confirm status, details and CheckedUtc on each test device.
6. **Configure your environment.** For 04, choose real service Name values in `-ServiceNamesCsv`. For 10, inventory direct admin membership and set `-AllowedSidsCsv`. Both defaults intentionally reveal assumptions that need your review.
7. **Choose one workflow per check.** Use a scheduled `-Mode Detect`/approved `-Mode Remediate` run, or a Script Result condition evaluating Detect and attaching a separate Remediate action. Do not duplicate their schedules.
8. **For condition-driven repair:** match exit code `1` AND output Contains `N1_RESULT=Issue`. Attach the same script with `-Mode Remediate` and matching settings, as SYSTEM. Enable script-error notifications. Reset when no longer met. Report-only checks should alert without a repair action.
9. **Query Devices → More Filters → Custom Fields.** Example: `n1DiskStatus` equals `Issue`. Save a group, add status columns, and inspect timestamps/last contact. Create a separate Error view.
10. **Expand after the pilot.** Begin with service start / disk / Fast Startup repairs that fit your policy. Firewall and required services have extra opt-in flags. Keep BitLocker resume and DISM repair on demand in approved windows. Reboot and local admin checks are report-only.

## Exact status contract

| Value | Exit code |
|---|---:|
| Healthy | 0 |
| Remediated | 0 |
| Issue | 1 |
| Error | 2 |
| NotApplicable | 0 |

All scripts default to **Detect**. Detect writes results but makes no endpoint repair. A repair becomes **Remediated** only when its follow-up check passes. Fields hold the last result, so always consider freshness.

## First condition example

**N1 - IME service health:** Evaluation script `N1-03-IntuneManagementExtension.ps1`, Detect, every 4 hours, timeout 120 seconds. Trigger exit 1 AND Contains `N1_RESULT=Issue`. Action: same script, `-Mode Remediate`, SYSTEM. A missing or disabled IME remains Issue for manual investigation.

See `README.md` for the complete field table, all parameters, reset/error handling, supported scope and troubleshooting. The scripts passed parsing and mock logic tests; live Windows/NinjaOne pilot testing remains required.
