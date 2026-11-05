# Hotfix 8: Read run logs in File Explorer

Earlier live runs granted full control to SYSTEM and the local Administrators
group. Ordinary File Explorer uses the user's non-elevated token, so even a local
administrator may be unable to browse that directory without elevation. The files
were not intentionally limited to SYSTEM alone.

## New runs

The default now grants the Explorer owner in the setup session **read/execute
access to that run folder and its contents**, while SYSTEM and Administrators keep
full control. The reader cannot modify/delete the logs or worker control files.
State and Runs parent folders grant folder-only navigation/listing access;
that reader permission does not inherit into Completed-*.json or other runs.

This works with the existing SYSTEM + ServiceUI launch. The resolved reader SID
is recorded in SetupUI.log. If the user cannot be identified, setup continues
with the explicit readers (if any) plus SYSTEM/Administrators, and records the
reason in the log. A SYSTEM process in session 0 needs explicit LogReaderSids.
The configured StateDirectory parent is not re-permissioned. If you deliberately
restricted that custom parent, its navigation permissions also need consideration.

Run-folder access covers transcripts, MSI/servicing logs and diagnostic JSON,
including request parameters. Do not put credentials into step parameters or
logs. This permission grants access; it does not redact existing file contents.

Optional settings inside **Behavior** (old JSON receives these defaults in memory):

```json
"AllowInteractiveUserToReadLogs": true,
"LogReaderSids": []
```

Set AllowInteractiveUserToReadLogs to false and leave LogReaderSids empty to keep
new runs restricted to SYSTEM/Administrators. Alternatively add exact Windows
user/group SID strings to LogReaderSids for additional readers. Group access
depends on that group's SID being present in the reader's Windows token. These
settings do not make anyone an administrator or grant write access.

Changing settings governs new run folders and current parent navigation grants;
it does not revoke read grants already attached to previous run folders. Keep an
additional support reader in LogReaderSids if that account must continue browsing
the parent folders after later launches by other users.

## Upgrade from hotfix 7

Replace **Start-DeviceSetup.ps1** and **Core/Setup.Common.ps1** together. Keep your
configuration, enterprise/custom steps and branding. No SetupVersion change or
completion-state reset is needed. Copy **Tools/Grant-SetupLogReadAccess.ps1** if
you want to grant access to logs created before this update.

The new default applies on the next live launch, including existing custom JSON
that omits the optional settings. Demo folders keep their normal user permissions.
The ACL changes apply to SYSTEM live execution; an administrator-only local pilot
with RequireSystemForLive=false keeps its existing inherited filesystem behavior.

## Access existing runs now

From the extracted package folder, open **Windows PowerShell as administrator**
using the same account whose File Explorer needs access, then run:

```powershell
.\Tools\Grant-SetupLogReadAccess.ps1 `
    -ConfigPath .\Config\Portal-Detection-Test.json `
    -AllRuns
```

Use the configuration that generated the logs: the tool uses its StateDirectory
and SetupId. For enterprise example runs, use Config/Enterprise-Example.json;
for your production runs, use your production JSON. The default ReaderSid is the
account running the repair tool. Without AllRuns it grants access only to the
latest run; `-RunName 'YYYYMMDD-HHMMSS-xxxxxxxx'` targets one run instead.

If running this from SYSTEM or with another administrator's credentials, supply
the intended Explorer user's SID explicitly:

```powershell
.\Tools\Grant-SetupLogReadAccess.ps1 `
    -ConfigPath .\Config\Portal-Detection-Test.json `
    -ReaderSid 'S-1-12-1-REPLACE-WITH-YOUR-REAL-SID' `
    -AllRuns
```

Obtain the real SID using `whoami /user` in the intended user's ordinary shell,
not the SYSTEM shell. The example SID above is deliberately a placeholder.

The repair tool grants read/execute on selected run folders, with child inheritance,
and folder-only access to the two parent folders. It preserves existing access
rules and does not take ownership, enable broad inheritance or change completion
state ACLs. It refuses run directory links. Files with separately protected ACLs
may still require individual administrative review; normal package-generated
logs inherit the run-folder grant. It does not launch app scripts.

## Validation

Static source/schema checks ran in the build environment. The new
Tests/Invoke-LogAccessTests.ps1 uses temporary NTFS directories on Windows to
check new/existing log inheritance, preserved SYSTEM/Administrators access,
read-only rights and exclusion of completion state/other runs. Run it from an
elevated Windows PowerShell session. These Windows ACL tests have not been run
in the Linux build environment. Also verify opening a log from ordinary File
Explorer and confirm the user cannot edit it.

[Microsoft: UAC and File Explorer tokens](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works)
