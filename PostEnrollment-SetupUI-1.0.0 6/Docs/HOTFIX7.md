# Hotfix 7: Company Portal SID detection

The reported "No valid SID could be determined" message is consistent with the
AppX cmdlet's direct `-User` query, rather than the custom Explorer-session error
messages. A script location/stack trace would be needed to confirm the precise
failing call on a particular device. It does not establish that Company Portal
is missing, or that the interactive user's SID is invalid.

## Changed detection

The shared helper now validates SID syntax without translating it to an account
name, then runs `Get-AppxPackage -AllUsers -Name <app>`. It verifies:

- Exact package name, Microsoft publisher, healthy status and no partial staging.
- A PackageUserInformation entry whose UserSecurityId exactly matches the
  interactive user and whose InstallState is Installed.

Another user's installation and a Staged entry do not count as success. AppX
query errors still fail the step; they do not become a missing-app result.
Explorer-owner selection is unchanged except for rejecting empty/service SIDs
and logging the selected SID/session in SetupUI.log. Session 0 still requires
an explicit, interactive TargetUserSid; no arbitrary profile is chosen.

This shared change applies to Company Portal detection, install verification,
Intune-wait polling, and Notepad detection. The registry flag's meaning is unchanged.

## Upgrade from hotfix 6

Replace **EnterpriseSteps/Enterprise.Common.ps1**. No JSON edits or state reset
are required. The full ZIP also includes updated tests/docs and a separate
**Config/Portal-Detection-Test.json** for verifying detection without installing
or removing applications. It writes the configured Company Portal registry flag.

Run that test configuration through your existing SYSTEM + ServiceUI launcher
with **-Live**. It has a separate SetupId and ResumeCompletedSteps=false, so each
launch checks again. Do not enable -Live on the entire enterprise template just
to test detection. No switch, or -Demo, still only simulates the UI.

For a read-only inventory check in SYSTEM/elevated Windows PowerShell 5.1:

```powershell
Get-AppxPackage -AllUsers -Name Microsoft.CompanyPortal -ErrorAction Stop |
    Format-List Name, Status, IsPartiallyStaged, PackageUserInformation
```

Look for the interactive user's SID with Installed, not just a package name.
The selected SID is recorded in SetupUI.log. If this inventory command also
fails, capture its full error and the step transcript; bypassing `-User` cannot
repair an underlying AppX service/repository problem.

## Validation

Static syntax/configuration/package checks ran in the build environment.
The Windows helper tests now cover other-user-only registration, a Staged target,
mixed users, an Entra-format SID, invalid/service SIDs, missing metadata and query
failure. Windows runtime tests remain unexecuted here; verify on your test device.

Microsoft references:

- [Get-AppxPackage and AllUsers](https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage?view=windowsserver2025-ps)
- [Package user SID and installation state](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packageuserinformation?view=winrt-26100)
