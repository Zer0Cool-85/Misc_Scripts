# Hotfix 9: WinGet first, offline fallback

Company Portal and modern Windows Notepad can now try WinGet first and use your
staged offline package if the app remains missing. This fits the existing
SYSTEM + ServiceUI workflow; the WPF window still runs exactly as before.

## Upgrade from hotfix 8

Close the running setup window and replace these files together:

- `EnterpriseSteps/Enterprise.Common.ps1`
- `EnterpriseSteps/Invoke-UserAction.ps1`
- `EnterpriseSteps/Step-InstallCompanyPortal.ps1`
- `EnterpriseSteps/Step-InstallNotepad.ps1`
- `EnterpriseSteps/Test-EnterpriseConfiguration.ps1`

Also copy the new `Tests/Invoke-WinGetFallbackTests.ps1` and documentation.
Preserve your branding, production JSON, payloads and customized step code;
merge these changes if you edited the supplied enterprise scripts.

In **both install steps** in your production JSON, change `Parameters.Mode` to
`WinGetThenOffline`. Keep your existing offline package, dependency and license
paths. This is the new default when Mode is omitted; an existing explicit
`OfflinePackage` setting continues to run offline only. `IntuneWait` and Notepad's
explicit `WindowsCapability` mode are still available.

The changed step scripts/parameters change their execution fingerprints, so
those steps can be reconsidered; healthy existing apps are detected and skipped.
There is no need to reset the whole setup state or bump SetupVersion for this
upgrade. Shared helper changes alone are not fingerprinted by the framework.

## What happens

1. SYSTEM resolves the signed-in user and checks that user's healthy AppX
   registration. An already installed app is skipped.
2. A temporary Task Scheduler task runs WinGet as that user with limited
   privileges and an existing interactive logon token; no credentials are stored.
3. SYSTEM checks the user's app registration again, allowing up to
   `WinGetVerifySeconds` for it to appear.
4. If still missing, SYSTEM provisions the configured offline bundle and the
   user helper registers it for the same user, as in the existing offline mode.
5. The step succeeds only after the target user's healthy registration verifies.
   Company Portal's `NeedsCompanyPortal` flag clears to 0 only after verification.

| App | Exact Microsoft Store ID | Verified package |
|---|---|---|
| Company Portal | `9WZDNCRFJ3PZ` | `Microsoft.CompanyPortal` |
| Windows Notepad | `9MSMLRH6LZF3` | `Microsoft.WindowsNotepad` |

WinGet is resolved from the current user's registered Microsoft App Installer
package. The command uses `--source msstore --exact --silent`, accepts the package
and source agreements, disables interactive prompts and requests silent
authentication. Review those agreement choices as part of your deployment.
The command does not specify `--scope machine`; it runs as the target user.
It does not try to use WinGet under SYSTEM, bootstrap App Installer or modify
source/policy settings. Microsoft explicitly says the WinGet CLI does not support
SYSTEM context; the limited-user task is why this fits your existing launcher.

## Configure the two steps

For Company Portal (merge into the existing step object):

```json
"Parameters": {
  "Mode": "WinGetThenOffline",
  "RegistryPath": "HKLM:\\SOFTWARE\\YourCompany\\PostEnrollmentSetup",
  "PackageRelativePath": "Payloads/CompanyPortal/CompanyPortal.appxbundle",
  "DependencyRelativePaths": [
    "Payloads/CompanyPortal/Dependencies/YourRequiredDependency.appx"
  ],
  "LicenseRelativePath": "Payloads/CompanyPortal/License.xml",
  "AllowUnlicensedPackage": false,
  "WinGetTimeoutSeconds": 600,
  "WinGetVerifySeconds": 30
},
"TimeoutSeconds": 2400
```

For Notepad:

```json
"Parameters": {
  "Mode": "WinGetThenOffline",
  "PackageRelativePath": "Payloads/Notepad/Notepad.msixbundle",
  "DependencyRelativePaths": [
    "Payloads/Notepad/Dependencies/YourRequiredDependency.appx"
  ],
  "LicenseRelativePath": "Payloads/Notepad/License.xml",
  "AllowUnlicensedPackage": false,
  "WinGetTimeoutSeconds": 600,
  "WinGetVerifySeconds": 30
},
"TimeoutSeconds": 2400
```

Filenames are examples. Use the actual approved bundle, required dependencies
and license from your offline kit. See [obtaining and staging official packages](ENTERPRISE-STEPS.md).
If a particular package permits unlicensed provisioning, you may explicitly set
`AllowUnlicensedPackage` to true and clear LicenseRelativePath. This does not
bypass signing, dependencies or policy. No payloads or licenses are bundled.

| Setting | Default | Allowed values / purpose |
|---|---|---|
| Mode | `WinGetThenOffline` | Both Store installers; explicit old modes retain their behavior |
| WinGetTimeoutSeconds | 600 | 30-1200 seconds for the launched WinGet process |
| WinGetVerifySeconds | 30 | 0-120 seconds to wait for user registration after WinGet exits |
| Step TimeoutSeconds | 2400 in the new examples | Overall UI time budget: include WinGet, 90 seconds of task overhead, verification, offline provisioning and up to 300 seconds of user registration |

The preflight requires a staged fallback bundle even if you expect WinGet to
work. Runtime does not touch those files if WinGet succeeds or the app is already
healthy; if fallback is needed and files are missing, the step fails with details.

`Config/Enterprise-Example.json` now uses this mode. For a focused pilot, use
[StoreApps-WinGet-Example.json](../Config/StoreApps-WinGet-Example.json), containing
only the two install steps. It uses a separate SetupId and disables completed-step
resume so every pilot launch rechecks app state. It never uninstalls existing apps
to force a test. Both files have payload placeholders to replace.

## Logs and failure handling

The existing **SetupUI.log** records the target SID, Store ID, attempt identifier,
task exit code, verification and offline fallback outcome. The hotfix 8 read-only
File Explorer access to the run folder is preserved.

Detailed WinGet logs are in the **signed-in user's** profile:

```text
%LOCALAPPDATA%\PostEnrollmentSetupUI\WinGet\<attempt-id>\
    Action.log
    WinGet.log
    stdout.log
    stderr.log
```

Action.log includes helper errors, the WinGet command and native exit code when
available. WinGet.log may not exist if WinGet could not start. The primary log
identifies the attempt folder; it does not import user-writable logs as trusted
SYSTEM evidence or grant the user write access to the primary run log. Offline
servicing and registration retain the existing DISM, user TEMP and event logs.
Include the user-side logs in your normal support collection/retention process.

Missing App Installer registration, disabled WinGet/msstore access, source/network
errors and unsuccessful installs normally lead to the offline attempt. A native
error does not force reinstallation if the app is actually present afterward;
Intune or Store deployment may have finished concurrently. Conversely, exit 0
without a verified registration triggers fallback. AppX inventory errors fail
the step rather than being interpreted as an absent app.

If WinGet times out, the helper attempts to stop only its launched process tree.
Confirmed cancellation leads to verification and then offline fallback if needed.
If cancellation/task completion cannot be confirmed, the step fails without
starting a second installer. Review the user logs and active deployment before
retrying. Windows servicing can continue inside a service after a client process
exits; a busy/version-conflict error from offline deployment still requires review.

Existing application control, Store source and AppX policies remain in force.
Blocking the Store UI alone is not the same as disabling WinGet's msstore source.
An offline payload is a connectivity fallback, not a policy bypass: policy that
blocks the app or AppX deployment can block that route too. A user sign-out can
prevent the temporary user task and registration from completing.

## Validate and pilot

From the extracted root in a fresh 64-bit Windows PowerShell 5.1 session:

```powershell
.\EnterpriseSteps\Test-EnterpriseConfiguration.ps1 -ConfigPath .\Config\StoreApps-WinGet-Example.json
.\Tests\Invoke-WinGetFallbackTests.ps1
.\Tests\Invoke-EnterpriseHelperTests.ps1
```

The first command reports missing placeholder payloads until you stage them.
The tests use mocks; they do not invoke live WinGet, install apps, write HKLM or
create scheduled tasks. For UI preview use `Start-DeviceSetup.ps1 -Demo` with that
config. Demo mode does not execute scripts. For real installs, point your existing
SYSTEM + ServiceUI launcher at the pilot config and retain **-Live**.

| Pilot case | Expected result |
|---|---|
| App already healthy for setup user | Neither installer is launched |
| Missing app; WinGet and msstore available | WinGet runs as the user; SYSTEM verifies; no offline deployment |
| WinGet missing, source denied or network unavailable | Failure recorded; staged offline route is attempted |
| WinGet returns zero but registration stays absent | Offline route is attempted |
| WinGet reports failure but registration exists | Success after verification; no duplicate offline deployment |
| Both routes fail / offline dependency or license missing | Failed UI step, clear logs; Portal flag remains 1 when known missing |
| App installed for another user only | Still treated as missing for the setup user |
| Task/process termination uncertain | Failed step; no automatic offline attempt |
| Retry after a successful installation | Current detection skips reinstalling the app |

Linux static syntax/configuration checks were run for this package. Windows
PowerShell runtime, WinGet/msstore, Task Scheduler, WPF/ServiceUI and real
offline installation tests could not be run in the authoring environment.
Run the supplied tests and live cases on an enrollment test device before rollout.

## Microsoft references

- [WinGet troubleshooting: SYSTEM context is unsupported](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)
- [WinGet install command and switches](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)
- [WinGet availability and first-logon registration](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [App Installer policies, including Microsoft Store source control](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-desktopappinstaller)
- [Intune Microsoft Store apps and Store UI policy behavior](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-microsoft-store)

WinGet-related documentation reviewed November 5, 2026.
