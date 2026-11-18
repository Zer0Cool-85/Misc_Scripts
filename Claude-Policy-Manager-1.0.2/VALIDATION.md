# Validation record

Package 1.0.2; November 18, 2026.

## Completed

- **69 portable engine checks** using PowerShell 7.4.6 on Linux: script parsing, configuration validation, all 12 policy conversions, Boolean/numeric bounds, UUID and JSON-array handling, path validation, conflicting instructions, merged configurations, enforcement idempotency, missing/wrong-type values, explicit removals, original-state preservation, uninstall planning, and a failing registry write.
- **13 transaction checks**: ran the actual installer/uninstaller scripts in separate PowerShell processes with Windows-only services replaced by test fixtures. Covered initial installation, a failure after task registration, restoration of previous files/state/registry/task definition, successful in-place update, retained restrictions, old-package uninstall skipping a newer install, and matching uninstall cleanup.
- **12 diagnostic checks**: missing engine, missing manifest, injected pre-logger folder failure, stage and position/stack reporting, failure detection with no stdout, detection logging and fallback, inaccessible log destination, and successful detection.
- **8 audit-access regression checks**: reproduced the exact reported enum-cast error, compiled the corrected production C# interop helper, and tested an extracted helper with only its native open call substituted. Verified native access mask/hive/path, missing-key/path results, and preserved native error codes 5 and 1314. Real native handles and SACL access were not exercised.
- Ran preparation in an isolated copy with the Config 1 example. Verified payload hashes, the generated detection script's manifest hash, and preservation of the unconfigured shipping source.
- Checked the event subscription as XML, including the two event IDs and the exact Claude key filter.
- ZIP contents are checked against the local source files when packaged.

## Not completed here

Native Windows CMD bootstrap/redirection and Windows PowerShell 5.1 execution, actual registry reads/writes, NTFS ACL application, Security audit-policy/SACL setup, generation of events 4657/4663, Task Scheduler COM registration/security, actual Claude behavior, and Intune installation/detection/removal require a Windows pilot.

Portable tests intentionally substitute the Windows registry, auditing, task service, and ACL side effects; passing them does not establish Windows integration success. The installer has verification and rollback paths, but an abrupt power loss or forced process termination cannot execute a catch/finally rollback.

Run the tests again from the extracted package if you edit the engine:

```powershell
.\Tests\Engine.Tests.ps1
.\Tests\Transaction.Tests.ps1
.\Tests\Diagnostics.Tests.ps1
.\Tests\AuditAccess.Tests.ps1
```

Follow the Windows pilot checklist in README.md before broad assignment.

The supplied Windows pilot log for 1.0.1 confirms native PowerShell 5.1, SYSTEM context, successful package/config validation and secured-folder initialization, and failure at the invalid RegistryRights cast in the audit snapshot. Those observations do not establish Windows integration success for the corrected 1.0.2 native helper.
