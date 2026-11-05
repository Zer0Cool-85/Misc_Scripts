# Writing your setup steps

## The execution contract

Each enabled step is executed sequentially in a fresh, hidden **64-bit Windows PowerShell 5.1** process. When the parent is launched as SYSTEM through your ServiceUI workflow, its workers also run as SYSTEM. A step does not share local variables or functions with another step.

The framework starts a transcript, supplies progress/installer helper functions, runs your script, and checks the process exit code. The UI remains on its own thread/process while the worker does the slow work.

1. Keep `$ErrorActionPreference = 'Stop'` in your script.
2. Detect the existing state before making changes. Steps must be safe to run again after interruption or failure.
3. Apply the change.
4. Verify the resulting state.
5. Return normally for success; `throw` a useful message for failure.

Returning `$false`, outputting the word `Failed`, or using `Write-Warning` does **not** mark a step failed.

## Minimal example

Replace a placeholder step with your own code using this pattern:

```powershell
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

Write-SetupProgress -Message 'Applying configuration...' -Percent 10

# Your real PowerShell commands go here.

Write-SetupProgress -Message 'Verifying the result...' -Percent 90

# Example: if your actual detection fails, throw a meaningful error.
# if (-not (Test-YourResult)) { throw 'The expected setting was not applied.' }

Write-SetupProgress -Message 'Configuration verified.' -Percent 100
```

This is a writing pattern, not a ready-made configuration action. The included `Steps/Step-XX.ps1` files retain a deliberate `throw` until you implement them, so an untouched placeholder cannot report success in production.

## Sending progress

```powershell
Write-SetupProgress -Message 'Downloading application files...'
Write-SetupProgress -Message 'Installing the application...' -Percent 45
Write-SetupProgress -Message 'Validating installation...' -Percent 95
```

`Message` updates the current card's detail line. Omitting `Percent` hides the per-step percentage bar while the spinner continues. Percentages are estimates you supply; the framework does not read an installer's internal progress. The overall bar weights each configured step equally and measures **finished work**, including failures/skips. Overall text and colors show whether the result succeeded.

## Running installers and preserving exit codes

Prefer the supplied helper:

```powershell
$installer = Join-Path $env:SETUP_PACKAGE_ROOT 'Files/AppSetup.exe'
$null = Invoke-SetupProcess -FilePath $installer -Arguments '/quiet /norestart'
```

`Invoke-SetupProcess` waits for the process tree, accepts 0 and 3010 by default, throws on other codes, and remembers a reboot-required result. Use the vendor's actual silent/no-restart arguments; EXE switches are not standardized.

Override acceptable codes when required:

```powershell
$null = Invoke-SetupProcess -FilePath $installer -Arguments '/S' -SuccessExitCodes @(0,3010) -RebootExitCodes @(3010)
```

For raw native commands, check the exit code immediately:

```powershell
& $installer /quiet /norestart
$installExit = $LASTEXITCODE
if ($installExit -notin @(0,3010)) { throw "Installer failed: $installExit" }
if ($installExit -eq 3010) { exit 3010 }
```

A final nonzero `$LASTEXITCODE` is preserved by the worker when the step returns. An explicit `exit N` is also honored. Earlier native failures can be overwritten by later native commands, so check each command or use the helper. If you intentionally handle a nonzero code and recover, return an explicit `exit 0` or reset `$global:LASTEXITCODE = 0` after verification. The JSON step's `SuccessExitCodes` controls final acceptance; `RebootExitCodes` must be a subset of it.

The framework displays a restart reminder and returns 3010 when needed. It does not reboot. Suppress automatic reboots in each installer so they cannot interrupt the checklist unexpectedly.

## Parameters

In your step script:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MsiRelativePath,
    [Parameter(Mandatory)][string]$ExpectedFile
)
```

In that step's JSON entry:

```json
"Script": "Examples/Step-InstallMsi.ps1",
"Parameters": {
  "MsiRelativePath": "Files/YourApplication.msi",
  "ExpectedFile": "C:/Program Files/Vendor/App/App.exe"
}
```

Parameters are passed as named PowerShell parameters, not evaluated as commands. Boolean JSON values can bind to boolean/switch parameters. Do not place passwords, tokens, or private keys in configuration or progress messages; request files and transcripts retain setup information.

## Environment available to every step

| Variable | Value |
|---|---|
| SETUP_PACKAGE_ROOT | Absolute directory containing Start-DeviceSetup.ps1 |
| SETUP_STEP_ID | Current JSON step ID |
| SETUP_RUN_DIRECTORY | This run's log and diagnostic directory |
| SETUP_PROGRESS_FILE | Internal current-step progress JSON path |

Use `$env:SETUP_PACKAGE_ROOT` to locate shared assets/installers. `$PSScriptRoot` inside a step refers to that step's own folder. Use the progress helper instead of writing progress JSON yourself.

## Dependencies, failures, and retry

- A step may depend only on **earlier enabled** step IDs.
- A failed/skipped dependency causes the dependent step to be skipped.
- With `StopOnRequiredFailure: false`, independent later steps can continue.
- With `StopOnRequiredFailure: true`, a required failure skips all remaining steps.
- Optional failures remain visibly failed but do not make the overall deployment fail if all required steps succeeded.
- **Retry unfinished** resets only failed/skipped included steps. Unselected options are excluded. Successful steps remain completed. Dependencies are checked again.
- There is no unlimited automatic retry loop.
- A timeout always stops the run and disables in-window retry. The framework asks Windows to terminate the worker process tree; a service-owned MSI/custom installer operation may outlive that tree. Inspect device/installer state before restarting the workflow.

## Completion and resume

With `ResumeCompletedSteps: true`, a successful step is remembered. Its fingerprint includes its script content, configured parameters, success/reboot codes, and dependency fingerprints. Changing a step or one of its declared dependencies causes affected work to run again. Changing only branding or wording does not.

External installer contents and helper files imported by your script are **not automatically fingerprinted**. Bump `SetupVersion` when those inputs change and you want steps reconsidered. Detection inside each step remains essential. A saved success is a record of previous execution, not continuous compliance monitoring.

## User-specific settings

These steps inherit SYSTEM. Reading or writing HKCU or APPDATA accesses the SYSTEM profile. Use your existing intentional user-context mechanism for settings that require the signed-in user; do not assume the visible window changes the worker's identity. This package does not introduce a separate user-context execution engine.

## Examples supplied

- `Examples/Step-InstallMsi.ps1`: local MSI, no-restart install, log, and simple file verification. Replace file-presence detection with version/product detection as appropriate.
- `Examples/Step-SetMachineSetting.ps1`: example machine-registry setting and verification.

Neither example runs unless you explicitly reference it from the JSON configuration and launch **-Live**.

## Optional app choices

Use Enabled=true, UserSelectable=true, Required=false to offer a script unchecked before the run. Required=false alone still runs automatically. Keep detection/idempotence inside optional scripts just as for required actions; selecting an app is not an installation check. All chosen scripts use the same SYSTEM worker and progress helpers. See [hotfix 4](HOTFIX4.md) for selection, dependency, retry, and remembered-decline behavior.

## Supplied enterprise steps

See [Enterprise steps](ENTERPRISE-STEPS.md) for configurable MSI installation with primary-log integration, Company Portal detection/installation, selective Office/OneDrive removal and Notepad installation. These scripts use the existing worker and do not replace your custom Steps folder.
