# Hotfix 4: optional installs and window branding

## Upgrade your customized package

Close the existing setup process. Copy these files together from the new package:

- Start-DeviceSetup.ps1
- Core/Setup.Common.ps1
- UI/MainWindow.xaml
- UI/StepViewModel.cs
- UI/TaskbarIdentity.cs (new)

Keep your own Config, Steps, Assets, and production launcher. If you changed XAML, merge those changes into the new template. Copy Tests/Invoke-SmokeTests.ps1 for the new regression checks. Run-Demo.cmd now includes -WindowStyle Hidden. The supplied live ServiceUI launcher already hides its PowerShell console.

Older JSON files still work. UserSelectable defaults to false and IconPath defaults to an empty string, which uses the built-in setup icon. New optional text keys also have defaults. Do not bump SetupVersion or reset completion state just for this framework update. The existing execution fingerprint algorithm is unchanged.

## Offer an app without installing it by default

Edit an existing step entry rather than adding an eleventh slot. Set these three properties:

```json
"Enabled": true,
"UserSelectable": true,
"Required": false
```

Here is a complete example that can replace slot 6. Put your installation/detection code in Steps/Step-06.ps1 and remove its placeholder throw:

```json
{
  "Id": "step06",
  "Enabled": true,
  "UserSelectable": true,
  "Title": "Install additional productivity tools",
  "Description": "Choose this if you need the additional tools for your role.",
  "Script": "Steps/Step-06.ps1",
  "Parameters": {},
  "TimeoutSeconds": 1200,
  "SuccessExitCodes": [0, 3010],
  "RebootExitCodes": [3010],
  "Required": false,
  "DependsOn": [],
  "DemoSeconds": 4,
  "DemoFailFirstAttempt": false
}
```

| Enabled | UserSelectable | Required | Result |
|---|---|---|---|
| false | Either | Either, subject to validation | Hidden and never offered/run |
| true | false or omitted | true | Runs automatically; failure blocks overall success |
| true | false or omitted | false | Runs automatically; failure produces a warning |
| true | true | false | Offered unchecked; runs only if the user selects it |
| Either | true | true | Invalid configuration; a step cannot be both required and opt-in |

When at least one unfinished option is available, the checklist first displays selection checkboxes. Automatic steps wait while the user chooses extras. **Start setup** locks the selection and runs automatic plus selected steps in JSON order. There is no timeout that silently selects or starts optional apps. A workflow with no available options starts automatically as before.

Unchecked items are reported as **Not selected**. They do not run, count toward progress, produce a warning, or become eligible for Retry unfinished. Selecting none is valid, including a configuration containing only user-selectable steps. Selected optional failures are visible warnings and can be retried. All enabled and disabled entries still share the ten-slot limit.

## Prerequisites

DependsOn still refers to earlier enabled step IDs. An automatic step cannot depend on an opt-in step; the validator rejects that configuration. A selected optional app can depend on automatic steps or other selected options. If its optional prerequisite is unchecked, Start setup displays a message asking the user to select it or uncheck the dependent app. It never silently selects another app. Previously completed prerequisites already satisfy the selection check.

## Later launches

With ResumeCompletedSteps=true, explicit declines are saved alongside successful completion records. If all work is complete or declined with matching execution fingerprints, a later live launch exits without showing another window. Decisions are device-level, not per signed-in user. Demo choices are not persisted to live state.

Add **-ChooseOptional** to your existing SYSTEM + ServiceUI launch to offer unfinished optional items again. Completed steps still remain completed. This is different from -ResetState, which resets the entire run's completion records. If a new or changed option causes the chooser to appear, other unfinished, previously declined options are also available again, unchecked.

An interrupted or failed selected app has no success/decline record, so it is offered unchecked on the next launch. With ResumeCompletedSteps=false, neither completion nor declines are reused. Execution-script/parameter/dependency changes invalidate matching fingerprints. Keep SetupVersion stable unless you intend a new setup revision.

## Window/taskbar icon

The default is a blue device/checkmark icon embedded as WPF drawing geometry. It requires no separate asset file. To use your logo, place a square ICO or PNG in Assets and add this under Branding:

```json
"IconPath": "Assets/company-setup.ico"
```

Use a real ICO file, not a renamed PNG. A multi-resolution ICO containing 16, 32, 48, and 256 pixel images is suitable. An empty IconPath uses the built-in icon. Keep IconPath package-relative. LogoPath and BannerPath are independent settings.

The icon is assigned to the WPF window, including its title bar, taskbar button, and Alt+Tab entry. The launcher sets a process AppUserModelID derived from SetupId, with a separate Demo suffix, before displaying the window. This separates grouping from ordinary PowerShell windows. Use a dedicated powershell.exe process and -WindowStyle Hidden to avoid a separate console taskbar entry. This is branding for the running window; no pinned shortcut/relaunch registration is installed, and Task Manager still lists powershell.exe.

## Transparent banner

BannerContainer now uses CanvasBrush, matching the window's light/dark background. It does not change AccentColor or other controls. Uniform + DownOnly remains the default sizing. Existing custom backgrounds can be merged into the XAML explicitly.

## Preview and verification

Run Run-Demo.cmd to see the two unchecked extras alongside the original automatic setup steps. For a shorter dependency/retry example:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo -ConfigPath .\Config\Optional-Demo.json
```

Try selecting only the last option; the chooser should ask for its prerequisite. Select both, start, and retry the intentionally failed last option. Also test leaving both unchecked. Run Tests/Invoke-SmokeTests.ps1 in Windows PowerShell 5.1 with -STA. Test the real taskbar icon under your SYSTEM + ServiceUI launch and normal Windows display scaling.

Static source/schema/XAML checks were run during authoring. Windows PowerShell execution, WPF rendering, checkbox interaction, taskbar grouping, SYSTEM resume, and real installations were not run in the Linux authoring environment.
