# Stage your approved installers here

No Microsoft or third-party installer binaries, offline licenses, or credentials are bundled.

Suggested folders: `MSI/`, `ODT/`, `CompanyPortal/`, `Notepad/`.

Use exact package-relative filenames in each step's Parameters. For Store packages,
keep the main APPX/MSIX bundle, required architecture-specific dependencies and
offline license XML together. See [the enterprise guide](../Docs/ENTERPRISE-STEPS.md).

Deploy the whole package to a local directory where SYSTEM and Administrators
have write access and Users have read/execute only. User registration must be able
to read its script, package and dependencies. Do not give users write access to
scripts or payloads that run as SYSTEM. Keep runtime logs in the existing protected
ProgramData state directory.

Company Portal and Notepad now default to WinGetThenOffline. Keep approved
offline bundles staged for that fallback; the enterprise preflight still checks
them. Runtime uses those files only if the app remains absent after WinGet.
See [hotfix 9](../Docs/HOTFIX9.md) for the new mode and timeout options.

For the ten-step profile, stage the entire Microsoft Get Help command-line kit under `GetHelp/` and keep the extracted Office Deployment Tool in `ODT/`. Run `Tools/Stage-WinGetClient.ps1` on your packaging workstation for machine-scope WinGet. Chrome and Drive normally download Google-signed installers when missing. See the [first-logon guide](../Docs/HOTFIX10.md).
