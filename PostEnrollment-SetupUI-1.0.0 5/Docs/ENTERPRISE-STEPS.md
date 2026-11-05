# Enterprise step scripts — updated for hotfix 9

Hotfix 9 adds [WinGet first with offline fallback](HOTFIX9.md) for both Store apps.
Hotfix 7 updates shared AppX detection; see [the SID detection fix](HOTFIX7.md).

Five configurable steps for your existing **SYSTEM + ServiceUI + WPF** workflow.
They use Windows PowerShell 5.1 x64 and the existing worker, progress, retry and
reboot reporting. No installer binaries or licenses are included.

## Upgrade your existing package

From hotfix 8, follow the five-file update and configuration instructions in
[Hotfix 9](HOTFIX9.md). The following framework instructions are for older packages.

From hotfix 4, copy **EnterpriseSteps/** and **Payloads/README.md**, and replace
**Core/Setup.Common.ps1** and **Start-DeviceSetup.ps1**. The two framework changes
only route primary-log writes through a shared append/retry helper. Merge that
change if you customized either file. Keep your production Config, Steps, Assets
and launcher. Earlier versions should first take all hotfix 4 framework files.

Add selected entries from [Enterprise-Example.json](../Config/Enterprise-Example.json)
to your own configuration. The existing 10-step limit includes these entries;
do not append five more entries to an already full ten-step file. You can use the
same MSI script in several steps with different parameters and unique IDs.

**The enterprise example is a template:** paths such as `YourApp.msi` and the
zero ProductCode must be replaced. `Run-Enterprise-Demo.cmd` previews all five
cards without running the scripts. Your normal default configuration is unchanged.

1. Stage your approved payloads and enter their exact relative filenames.
2. Choose the Office removal scope and Company Portal/Notepad install modes.
3. Copy the desired step objects into your production JSON, preserving ordered dependencies.
4. Run the preflight below against that JSON. It checks configuration, parameter
   names and explicitly listed file paths; it does not install anything.
5. Pilot the live configuration using your current SYSTEM + ServiceUI launcher.
   Change its `-ConfigPath` to your tested JSON; retain `-Live` for real execution.

```powershell
# From the extracted package root, in 64-bit Windows PowerShell:
.\EnterpriseSteps\Test-EnterpriseConfiguration.ps1 -ConfigPath .\Config\Enterprise-Example.json
.\Tests\Invoke-SmokeTests.ps1
.\Tests\Invoke-EnterpriseHelperTests.ps1
.\Tests\Invoke-WinGetFallbackTests.ps1
```

Preflight intentionally reports missing payloads in the unmodified template.
When switching a step to IntuneWait or WindowsCapability, remove the unused
offline payload parameters, or preflight will still check those listed paths.
Disabled steps are not checked. A missing dependency/license can still fail a
real deployment even when preflight passes.

Run the package from a **local, admin-controlled directory**. SYSTEM and
Administrators need write access; Users need read/execute on the user helper and
Store payloads, but must not be able to modify scripts, configuration or payloads.
The existing protected ProgramData state/log directory stays separate. ServiceUI
must target the intended Explorer session. These steps assume one first-logon
user, not an RDS/shared-device deployment across every existing profile.

## Common behavior and logs

- Human-readable progress, outcomes and errors go to the current run's
  **SetupUI.log**, alongside the UI's entries. Worker transcripts remain separate.
- Existing successful steps are resumed by the framework. Re-running a script
  also checks current detection state before installing.
- Exceptions fail the step and appear in the UI; native MSI 3010 reports a
  restart requirement. No supplied script initiates a reboot.
- Use `SuccessExitCodes: [0, 3010]` and `RebootExitCodes: [3010]` as in the example.
- Set the UI timeout comfortably above the installer duration, busy retries,
  Store registration and Intune wait. A UI timeout is not a safe installer
  cancellation mechanism. Inspect device state before retrying a timed-out install.
- Imported helper files and payload bytes are not part of the existing step
  fingerprint. Use a new, deliberate `SetupVersion` for a changed deployment
  release when you need completed steps reconsidered. Re-running cleanup after
  production apps are installed can remove matching apps again; review its scope.
- Detection is point-in-time. This first-logon UI does not replace ongoing Intune
  application detection, compliance, or update management.

The interactive helper uses a temporary Task Scheduler task running as the
identified user with **limited privileges and no stored password**. SYSTEM
independently checks the resulting app/registry state. It does not trust a
user-writable success marker. The task is stopped/unregistered in normal cleanup;
after a forced power-off, remove stale `PostEnrollment-UserAction-*` tasks during
your pilot cleanup. They have no trigger and a bounded execution time.

## 1. MSI installer

**Script:** `EnterpriseSteps/Step-InstallMsi.ps1`

```json
"Parameters": {
  "MsiRelativePath": "Payloads/MSI/YourApp.msi",
  "ProductCode": "{REPLACE-WITH-THE-REAL-MSI-PRODUCT-GUID}",
  "MinimumVersion": "1.2.3",
  "Properties": ["DESKTOPSHORTCUT=0", "COMPANYNAME=\"Example Company\""],
  "ExpectedSha256": "",
  "RequireValidSignature": true,
  "AppendVerboseLogToPrimary": true,
  "BusyRetries": 3,
  "BusyRetrySeconds": 30
}
```

Use the MSI **ProductCode**, not UpgradeCode or PackageCode. Obtain it from the
vendor/MSI metadata or an approved test installation's uninstall key. A changed
ProductCode on a major upgrade needs updated detection configuration. Detection
uses the two machine uninstall registry views and optional minimum DisplayVersion;
it never queries `Win32_Product`. Version strings must be .NET-style numeric
versions (for example `1.2.3`, not `1.2.3-beta`). Per-user MSI installs and products
that intentionally omit those machine uninstall keys need custom detection.

The script runs `/qn /norestart`, forces `ALLUSERS=1` and `REBOOT=ReallySuppress`,
and accepts MSI properties as an array. It rejects scope/reboot overrides and
does not support raw installer switches, transforms or EXE installers. Test your
vendor's silent installation contract first. A valid Authenticode signature is
required by default; `ExpectedSha256` optionally pins the exact approved file.
For a legitimately unsigned internal MSI, explicitly set RequireValidSignature
false and pin its approved hash.

It retries 1618 (another installation in progress), accepts 0/3010, and verifies
ProductCode/version afterward. Other codes fail. A success exit code with failed
detection is a failure, not a green checkmark.

The native `*-MSI-*.log` is kept separately. By default, its contents are appended
to **SetupUI.log after msiexec exits**, tagged `[MSI]`. This avoids two programs
writing different formats to the same file. Live UI messages are milestones,
not an invented MSI percentage. Set AppendVerboseLogToPrimary false for summary
entries and a path to the verbose log. Installer logs can expose property values;
do not pass secrets in Properties and protect/retain logs according to policy.

## 2. Company Portal detection and registry flag

**Script:** `EnterpriseSteps/Step-DetectCompanyPortal.ps1`

```json
"Parameters": {
  "RegistryPath": "HKLM:\\SOFTWARE\\YourCompany\\PostEnrollmentSetup"
}
```

In the native 64-bit registry view, this writes:

| Value | Type | Meaning |
|---|---|---|
| NeedsCompanyPortal | DWORD | 1 = missing/unhealthy for the setup user; 0 = present and healthy |
| TargetUserSid | String | User whose app registration was checked |
| CheckedUtc | String | UTC time of the latest check |
| DetectionScope | String | `InteractiveUserRegistration` |

The script resolves the owner of Explorer in the setup process's session. You
may explicitly supply `TargetUserSid` for an already interactive Explorer user;
it will not select an arbitrary other user if identification fails. It queries
`Microsoft.CompanyPortal` using AllUsers, then requires that user's exact SID
with InstallState=Installed, Microsoft publisher, Status=Ok and no partial staging. Merely being provisioned or installed for another user does not
count as ready. A missing app is logged and flagged **without failing the step**,
so its dependent installer can run. Registry/API errors do fail the step.

This tells you whether Portal is available **at this check**. It cannot prove
whether enrollment installed it earlier or whether someone removed it afterward.
The flag is a current-state marker, not immutable enrollment history.

## 3. Company Portal installation

**Script:** `EnterpriseSteps/Step-InstallCompanyPortal.ps1`

My preferred enterprise owner is an Intune **Microsoft Store app (new)** Required
assignment with **System** install behavior. Microsoft documents this for the
Autopilot device group. Keep that assignment for servicing, and make sure a custom
fallback does not compete with a second application deployment of the same app.

There are three modes:

| Mode | What the step does |
|---|---|
| WinGetThenOffline (default) | Tries the exact msstore ID as the signed-in user, verifies registration, then uses the configured offline route if still absent; see [Hotfix 9](HOTFIX9.md) |
| OfflinePackage | Provisions your staged official package/dependencies/license as SYSTEM, then installs/registers it for the interactive user if necessary; verifies that user's registration |
| IntuneWait | Polls for the Required Intune installation, up to WaitSeconds (default 300); fails if still absent. This observes installation and **does not force or trigger Intune deployment** |

The installer rechecks the actual app before acting, even if the registry flag
said it was missing. This handles Intune finishing between the two steps. It
updates the flag to 1 before remediation and clears it to 0 only after detection
succeeds. Use the same RegistryPath in both scripts. Configure
`"DependsOn": ["portal_check"]` on the install step if using the supplied IDs.

For Intune-managed delivery:

```json
"Parameters": {
  "Mode": "IntuneWait",
  "RegistryPath": "HKLM:\\SOFTWARE\\YourCompany\\PostEnrollmentSetup",
  "WaitSeconds": 300
}
```

For WinGet first with an immediate offline fallback, use these parameters (actual filenames vary). Set Mode to OfflinePackage if you want only the local route:

```json
"Parameters": {
  "Mode": "WinGetThenOffline",
  "RegistryPath": "HKLM:\\SOFTWARE\\YourCompany\\PostEnrollmentSetup",
  "PackageRelativePath": "Payloads/CompanyPortal/CompanyPortal.appxbundle",
  "DependencyRelativePaths": [
    "Payloads/CompanyPortal/Dependencies/x64/DependencyFromYourDownload.appx"
  ],
  "LicenseRelativePath": "Payloads/CompanyPortal/LicenseFromYourDownload.xml",
  "AllowUnlicensedPackage": false,
  "WinGetTimeoutSeconds": 600,
  "WinGetVerifySeconds": 30
}
```

### Obtain official Store payloads on your packaging workstation

Option A for Company Portal: Microsoft publishes an official **Company Portal
preinstall ZIP** for customers who cannot use the Store. Download and extract
the kit from the [Microsoft Download Center](https://www.microsoft.com/en-us/download/details.aspx?id=108156).
Use its real main app bundle, required dependencies and license where provided.
Review its supplied deployment instructions. Check version currency; the kit may
lag behind the Store. Do not feed the ZIP itself to Add-AppxProvisionedPackage.

Option B: use a current WinGet installation on your **administrator packaging
workstation**, not inside the SYSTEM step:

```powershell
winget download --id 9WZDNCRFJ3PZ --source msstore --exact --architecture x64 --download-directory C:\Packaging\CompanyPortal --accept-source-agreements --accept-package-agreements
winget download --id 9MSMLRH6LZF3 --source msstore --exact --architecture x64 --download-directory C:\Packaging\Notepad --accept-source-agreements --accept-package-agreements
```

Microsoft documents that Store offline license retrieval needs Entra
authentication and an eligible role (Global Administrator, User Administrator or
License Administrator). Use the least privilege available. Availability is
app/tenant dependent. If download/licensing is unavailable, retain Intune-managed
delivery instead of scraping unofficial download sites.

Copy the downloaded main bundle, dependency packages and license XML into the
package's Payloads subfolder. List **every required dependency explicitly**,
including the architecture variants the bundle needs. Do not guess dependency
names, omit them, or indiscriminately mix versions from old downloads. Keep the
downloaded names or rename them consistently in JSON. Test against your Windows
builds and architecture. The sample package targets x64 Windows; ARM64 needs its
own reviewed payload set and pilot.

`AllowUnlicensedPackage: true` maps to DISM SkipLicense. Only use it after verifying
that the particular package supports unlicensed provisioning. WinGet's ability
to download with `--skip-license` is **not** proof of that. Windows validates the
app signatures during deployment; the scripts do not install certificates or
disable package checks.

SYSTEM provisioning and signed-in-user registration are separate operations.
Registration uses the bundled limited-user task helper; it is not an
`Add-AppxPackage` call run as SYSTEM. AppX policy, architecture, dependencies,
package version conflicts or an unavailable user session can fail the step.
Review the per-step DISM log, Windows AppXDeploymentServer event log and
`%TEMP%\PostEnrollment-UserAction.log` in the **user's** profile. The primary log
records the action and failure; detailed AppX diagnostics stay in those logs.

## 4. Remove selected Office products and OneDrive

**Script:** `EnterpriseSteps/Step-RemovePreinstalledOfficeOneDrive.ps1`

Default scope:

| Setting | Default | Effect |
|---|---|---|
| OfficeProductIds | `["O365HomePremRetail"]` | Targets the consumer Microsoft 365/Office trial suite only |
| OdtRelativePath | `Payloads/ODT/setup.exe` | Your extracted, current Office Deployment Tool executable |
| AllowBusinessOfficeRemoval | false | Rejects broader suite removal unless deliberately enabled |
| RemoveOfficeHub | true | Removes `Microsoft.MicrosoftOfficeHub` registrations and provisioning (may appear as the Microsoft 365/Copilot hub) |
| RemoveStoreOfficeDesktop | false | Optional removal of Store-delivered `Microsoft.Office.Desktop`; requires the broader-removal acknowledgement |
| RemoveOneDrive | true | Uninstalls machine-wide OneDrive and the interactive user's per-user installation |
| ForceCloseApps | false | Fails if targeted Office/OneDrive processes are running; asks for closure/sync completion before retry |

Download and extract the [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117)
on your packaging workstation, then place its **setup.exe**, not the self-extracting
download EXE, at the configured path. A valid Microsoft signature is required.
The script reads Click-to-Run ProductReleaseIds, intersects them with your exact
allowlist, and generates an ODT XML with **Remove All="FALSE"** and those products.
It does not broadly remove Visio/Project, MSI-era Office or every product with
"Office" in its display name. ODT is only needed at runtime if an allowlisted
Click-to-Run product is found; preflight checks the explicitly supplied file anyway.

If you intentionally need to remove preinstalled business suites too:

```json
"OfficeProductIds": ["O365HomePremRetail", "O365BusinessRetail", "O365ProPlusRetail"],
"AllowBusinessOfficeRemoval": true,
"RemoveStoreOfficeDesktop": true
```

**A product ID does not reveal whether an OEM or IT installed it.** Those expanded
settings can remove a licensed managed suite with a matching ID. Run cleanup
before your managed Office installation, and exclude it from later deployment
versions unless removal is still intended. Keeping only the default consumer ID
does not remove every possible Office365 preinstallation; use inventory from
your actual OEM images to choose the allowlist.

OneDrive removal invokes its Microsoft-signed uninstaller and verifies uninstall
registration disappears. Machine binaries must be under Windows or Program Files;
user uninstallers execute as that user, never as SYSTEM. The recognized command
format is a quoted OneDriveSetup.exe path with `/uninstall`; unfamiliar formats
fail for review instead of being executed. Other existing users' installations,
the OS's bundled setup stub, OneDrive data folders and cloud files are left alone.
Do not interpret successful cleanup as all-profile removal on a shared device.

ForceCloseApps true can discard unsaved Office work or interrupt syncing; leave
it false for normal first-logon use. Removal does not configure a permanent
OneDrive block. If your organization excludes OneDrive, also review later Office
deployment choices and applicable Intune policy so another deployment does not
install it again. The script does not take ownership of files or delete synced data.

## 5. Install Windows Notepad if absent

**Script:** `EnterpriseSteps/Step-InstallNotepad.ps1`

For modern Notepad (`Microsoft.WindowsNotepad`), use the same WinGetThenOffline
parameters and offline staging workflow as Company Portal, with files under
Payloads/Notepad. WinGet uses the exact msstore ID `9MSMLRH6LZF3`.
An explicit OfflinePackage mode still runs only the staged package route. It verifies the interactive user's package, not just the
existence of `System32\notepad.exe`, which is insufficient for modern app readiness.
IntuneWait is also available when you assign Notepad through Intune.

If you only need the classic text editor, a simpler option is:

```json
"Parameters": {
  "Mode": "WindowsCapability",
  "CapabilitySource": "",
  "LimitAccess": false
}
```

This checks/installs the image's `Microsoft.Windows.Notepad*` capability via
Add-WindowsCapability. Microsoft describes this as the **older classic Notepad**,
not the modern Store app with tabs and newer features. It never silently falls
back from a failed modern install to classic. If modern Notepad is already healthy,
all modes skip installation. If the image exposes no matching capability, this
mode fails with guidance to use the Store package.

CapabilitySource optionally points to an approved matching Features on Demand
source. LimitAccess true prevents contacting Windows Update; a suitable source
is then needed if content is unavailable locally. With default settings, servicing
still obeys your Windows Update/WSUS/FoD policies. The script does not change
those policies to get around a content-source error. A reported RestartNeeded
propagates through the existing UI.

## Enterprise additions I would prioritize

These are recommendations, not extra changes silently executed by this pack.
Keep enforcement in your existing Intune policies/application assignments, and
use setup steps to verify the prerequisites for a usable first desktop.

| Priority | Suggested check/step | Suggested ownership |
|---|---|---|
| 1 | Required application/version health, Company Portal, VPN and authentication agent readiness | Existing Intune app assignments; UI verifies the user's usable result |
| 2 | BitLocker protection and recovery-key escrow status | Intune endpoint-security disk encryption policy and tenant reporting; local encryption status alone does not prove successful escrow |
| 3 | Endpoint protection service and onboarding health | Your licensed endpoint-security solution; do not assume EMS E3 includes every Defender for Endpoint feature |
| 4 | Device/user certificates and corporate Wi-Fi/VPN connectivity | Intune certificate/network profiles; verify the required certificate thumbprint/EKU/expiry without exporting private keys |
| 5 | Dell driver/firmware readiness and pending reboot | Your approved Dell update tooling and update policy; schedule BIOS changes with power checks and a controlled restart |
| 6 | Free disk space, AC power and service-endpoint connectivity before large installs | Small local preflight check; test the actual endpoints/proxy path rather than generic internet ping |
| 7 | Final restart-required summary | Existing 3010 handling plus a user-visible restart instruction; let your deployment owner schedule the restart |
| 8 | Setup log retention and a support-friendly result summary | Protected local logs, retention policy and your approved support collection process |

For this UI, my first extras would be **readiness preflight**, **required agent/
connectivity verification**, and **final restart guidance**. Keep security policy
changes, recurring updates and broad registry tuning out of a one-time installer
step unless there is a specific gap. These recommendations do not depend on
Intune Remediations or Windows Autopatch.

## Windows pilot checklist and known limits

Static PowerShell/C# parsing, JSON schema, script references, UI bindings and
configuration checks were run in the build environment. **No Windows app install,
uninstall, Task Scheduler, DISM, WPF or ServiceUI runtime test was run there.**
The helper tests are supplied for Windows and are also unexecuted in the build
environment. Run them and the following live checks on a disposable enrollment
test device before production use.

| Scenario | Expected result |
|---|---|
| WinGet succeeds / is unavailable / cannot verify registration | Verify and skip offline / attempt offline / attempt offline; see the [hotfix 9 pilot matrix](HOTFIX9.md) |
| MSI already detected | Skip installer; success recorded |
| MSI absent | Install, log summary + verbose text, then verify ProductCode/version |
| MSI 1618 / 3010 / 1603 | Bounded retry / success with restart required / failure with diagnostic log |
| Portal installed for another user only | NeedsCompanyPortal remains 1 for setup user |
| Portal missing, then installed | Detection succeeds with flag 1; installer clears it only after user registration verifies |
| Intune completes between Portal steps | Installer recheck skips duplicate installation and clears flag |
| Missing license/dependency or wrong architecture | Step fails; no false success based only on provisioning |
| User task denied by policy or user signs out | Step fails with actionable user-action/AppX diagnostics |
| Office consumer suite alongside Visio/business suite | Only explicitly allowlisted products removed; verify retained products still launch |
| Office/OneDrive running | Stops before removal unless ForceCloseApps explicitly enabled |
| Machine and current-user OneDrive | Both targeted installations checked; local sync folders preserved |
| Notepad modern versus capability | Correct app verified; capability mode documented as classic editor |
| Retry / second launch | Successful steps resume; failed steps recheck current detection before acting |

Additional limits: no generic MSI upgrade-code matching; no per-user MSI
deployment; no MSI-era Office cleanup; no all-profile OneDrive removal; no forced
Intune refresh/IME registry manipulation; no installer rollback. ODT/DISM and
native installers can complete asynchronously or require reboot. Review native
logs when post-detection fails instead of assuming the device is unchanged.

## Microsoft references

- [Company Portal: Intune Required System assignment](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-company-portal-autopilot)
- [Company Portal official offline kit](https://www.microsoft.com/en-us/download/details.aspx?id=108156)
- [WinGet download and offline license requirements](https://learn.microsoft.com/en-us/windows/package-manager/winget/download)
- [Add-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/add-appxprovisionedpackage?view=windowsserver2025-ps)
- [Office Deployment Tool configuration](https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options)
- [OneDrive per-machine versus per-user installation](https://learn.microsoft.com/en-us/sharepoint/per-machine-installation)
- [Notepad classic Features on Demand](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod?view=windows-11)
- [BitLocker policy and reporting](https://learn.microsoft.com/en-ie/intune/device-configuration/endpoint-security/encrypt-bitlocker-windows)

Base enterprise documentation reviewed October 22, 2026; WinGet flow updated November 5, 2026. Verify download contents and pilot
against your supported Windows builds when preparing each production release.
