# Configuration reference

Edit `Config/Setup.json` with a text editor. JSON requires double quotes, lowercase `true`/`false`, and no comments or trailing commas. Forward slashes in paths work on Windows and avoid JSON backslash escaping. Run `Validate-Config.cmd` after editing.

All listed keys are present in the examples. BannerStretch, BannerStretchDirection, IconPath, UserSelectable, and the selection-screen text fields are optional and default as shown when omitted; keep the other keys unless you modify the validator as well. Unknown fields are not a supported extension mechanism. There can be **1-10 total step entries**, with at least one enabled. To add your own step, edit an existing disabled slot or replace the list with your own entries.

## Identity

| Setting | Default | Meaning |
|---|---|---|
| `SchemaVersion` | `1` | Keep at 1 for this package format. |
| `SetupId` | `"Company.DeviceSetup"` | Stable package identity and state/mutex namespace. Letters, digits, dot, underscore, and hyphen; 1-80 characters. |
| `SetupVersion` | `"1.0.0"` | Change when you intentionally want a new setup revision. 1-40 safe characters. |

## Branding

| Setting | Default | Meaning |
|---|---|---|
| `CompanyName` | `"YOUR COMPANY"` | Displayed next to the optional logo; an empty string hides the company text. |
| `WindowTitle` | `"Welcome \| Device setup"` | Native Windows title bar text. |
| `Heading` | `"Welcome to your new PC"` | Large welcome heading. |
| `Message` | `"Please wait while we finish device setup. We are preparing your applications, access, and preferences."` | Welcome text beneath the heading. Wraps automatically; keep it to a short paragraph. |
| `IconPath` | `""` | Optional package-relative ICO/PNG. Empty uses the built-in setup icon; applies to title bar, taskbar, and Alt+Tab. |
| `LogoPath` | `""` | Relative PNG/JPG/BMP path, e.g. Assets/company-logo.png. Empty hides the logo. |
| `BannerPath` | `""` | Relative PNG/JPG/BMP path. Empty hides the full-width banner. |
| `BannerHeight` | `110` | Banner region height in WPF device-independent units; 40-240. Sets the available area, not a forced image height. |
| `BannerStretch` | `"Uniform"` | Optional. Uniform preserves the whole image and its aspect ratio. UniformToFill fills/crops. None keeps natural size. Fill changes aspect ratio to fill the region. |
| `BannerStretchDirection` | `"DownOnly"` | Optional. DownOnly prevents enlargement; Both permits enlargement and shrinking; UpOnly permits enlargement only. Has no effect with Stretch=None. |
| `LogoMaxWidth` | `180` | Maximum logo width; 24-400. Aspect ratio is preserved. |
| `LogoMaxHeight` | `48` | Maximum logo height; 24-120. Aspect ratio is preserved. |

## Appearance

| Setting | Default | Meaning |
|---|---|---|
| `Theme` | `"Light"` | Light or Dark. The Dark-Demo.json example includes brighter accent/status colors for dark backgrounds. |
| `AccentColor` | `"#2563EB"` | Primary buttons, current-step spinner/border, and progress. Hex #RRGGBB. |
| `SuccessColor` | `"#16815D"` | Success status/checkmarks. Hex #RRGGBB. |
| `FailureColor` | `"#C53F4E"` | Failure status/crosses. Hex #RRGGBB. |
| `WarningColor` | `"#A86D0B"` | Warnings and restart reminder. Hex #RRGGBB. |
| `WindowWidth` | `900` | Preferred width; 640-1600. Clamped to available desktop work area. |
| `WindowHeight` | `820` | Preferred height; 520-1200. Clamped to available desktop work area; step list scrolls. |
| `Topmost` | `true` | Keep the window above ordinary application windows. |
| `ReduceMotion` | `false` | Disable spinner rotation. The Running state and progress remain visible. |
| `ShowElapsedTime` | `true` | Show total elapsed time and per-step duration. |
| `ShowStepNumbers` | `true` | Show numbers in pending-step circles. |
| `FontFamily` | `"Segoe UI"` | Installed Windows font family. Segoe UI is the default. |

## Text

| Setting | Default | Meaning |
|---|---|---|
| `SelectionHeading` | `"Choose optional apps"` | Optional heading shown before setup when unfinished user-selectable steps exist. |
| `SelectionMessage` | `"Select any extras you would like, then start setup. Required setup runs automatically."` | Optional instructions while choosing. |
| `StartButton` | `"Start setup"` | Optional button label that submits choices and begins the run. |
| `SelectionFooter` | `"Optional apps are unchecked by default."` | Optional footer during selection. |
| `SelectStepLabel` | `"Include this optional step"` | Optional checkbox label. |
| `RunningHeading` | `"Getting things ready"` | Status-panel heading while steps run. |
| `RunningMessage` | `"Your settings and applications are being prepared."` | Status-panel supporting text while steps run. |
| `SuccessHeading` | `"Your PC is ready"` | Status-panel heading after all steps succeed. |
| `SuccessMessage` | `"All included setup steps have finished. You can start using your device."` | Status-panel supporting text after all steps succeed. |
| `WarningHeading` | `"Ready, with a few things to review"` | Heading when required steps succeeded but optional work failed/skipped. |
| `WarningMessage` | `"Required setup is complete. An optional step needs attention."` | Supporting text for that optional-issue outcome. |
| `FailureHeading` | `"A few things need attention"` | Heading when required work failed/skipped. |
| `FailureMessage` | `"Review the highlighted steps, then retry or contact your IT service desk."` | Supporting text after failure. |
| `Footer` | `"Keep your device plugged in and connected."` | Short instruction at the bottom of the window. |
| `Support` | `"Need help? Contact your IT service desk."` | Plain-text help/contact information. Does not launch an email client or browser. |
| `RetryButton` | `"Retry unfinished"` | Label for retrying failed/skipped steps. |
| `CloseButton` | `"Done"` | Result-screen close button label. |
| `CopyButton` | `"Copy details"` | Copy-diagnostics button label. |
| `DetailsLabel` | `"Setup details"` | Footer diagnostics expander label. |

## Behavior

Hotfix 8 adds optional `AllowInteractiveUserToReadLogs` (default true) and `LogReaderSids` (default empty array). These grant read-only access to new live run folders in SYSTEM mode. Existing JSON receives the defaults in memory. Completion-state files keep their protected ACLs. See [log access](HOTFIX8.md) for examples and existing-run repair.

| Setting | Default | Meaning |
|---|---|---|
| `RequireSystemForLive` | `true` | Default true. Live mode requires SID S-1-5-18. For a controlled local admin pilot you may set false in a separate config; this does not elevate the process. |
| `ResumeCompletedSteps` | `true` | Remember successful steps and declined options on later live runs. -ChooseOptional reoffers unfinished options without resetting successes. |
| `StopOnRequiredFailure` | `false` | True skips all remaining steps after a required failure. False continues independent work. Dependencies are always respected. |
| `AllowRetry` | `true` | Show Retry unfinished for failures/skips. Timeout/controller faults disable retry regardless of this value. |
| `AutoCloseSuccessSeconds` | `0` | 0 leaves the results open. Otherwise closes 1-3600 seconds after full success; does not auto-close warnings/failures. |
| `PollIntervalMilliseconds` | `400` | UI update interval, 200-2000 ms. Spinner animation uses WPF animation independently. |
| `StateDirectory` | `"%ProgramData%/Company/PostEnrollmentSetupUI"` | Absolute local directory after environment-variable expansion. SetupId is appended. Default uses ProgramData; do not use a network path. |

## Each step

| Setting | Example | Meaning |
|---|---|---|
| `Id` | `"step01"` | Stable unique identifier; 1-40 letters/digits/underscores/hyphens. Also used in log filenames and DependsOn. |
| `Enabled` | `true` | False omits the entry entirely. At least one step must be enabled. |
| `UserSelectable` | `false` | Optional. True offers an unchecked user choice; requires Required=false. False/omitted keeps automatic execution. |
| `Title` | `"Device readiness"` | Main card label. |
| `Description` | `"Check that the device is ready for final setup."` | Short explanation. Choice steps add Choose to install; automatic non-required steps add Non-blocking. |
| `Script` | `"Steps/Step-01.ps1"` | Package-relative .ps1 path; must exist for enabled steps. |
| `Parameters` | `{}` | JSON object of named PowerShell parameters supplied to the script. |
| `TimeoutSeconds` | `1200` | Whole-step execution limit, 1-86400 seconds. Includes child installer waits. |
| `SuccessExitCodes` | `[0, 3010]` | Final worker exit codes considered successful. Default 0 and 3010. |
| `RebootExitCodes` | `[3010]` | Successful codes indicating a reboot is required. Must also be listed in SuccessExitCodes. |
| `Required` | `true` | False makes failure non-blocking but does not prevent automatic execution. Set UserSelectable=true as well for opt-in installation. |
| `DependsOn` | `[]` | Earlier enabled IDs that must succeed first. Automatic steps cannot depend on user-selectable steps. Selected options require their optional prerequisites to be selected or already complete. |
| `DemoSeconds` | `4` | Simulated step duration, 1-60 seconds. Ignored in live mode. |
| `DemoFailFirstAttempt` | `false` | Intentionally fail this demo step on its first attempt, then pass on retry. Ignored in live mode. |

## Common customizations

### Company branding

```json
"Branding": {
  "CompanyName": "Your Company",
  "WindowTitle": "Your Company | Device setup",
  "Heading": "Welcome to your new PC",
  "Message": "Please wait while we finish device setup.",
  "IconPath": "Assets/company-setup.ico",
  "LogoPath": "Assets/company-logo.png",
  "BannerPath": "Assets/company-banner.jpg",
  "BannerHeight": 110,
  "BannerStretch": "Uniform",
  "BannerStretchDirection": "DownOnly",
  "LogoMaxWidth": 180,
  "LogoMaxHeight": 48
}
```

The file paths above require your actual image files. Leave either path empty when you do not want that image. See `Assets/README.md` for sizes and cropping behavior.

### Banner sizing

The default Uniform + DownOnly combination keeps the whole image visible, preserves its aspect ratio, and only shrinks it when necessary. The image is centered in the fixed-height banner region. Unused space matches the main window background (CanvasBrush). Lower BannerHeight if you want a shorter header; the supported range is 40-240.

| Desired result | BannerStretch | BannerStretchDirection |
|---|---|---|
| Entire image visible, no enlargement (default) | Uniform | DownOnly |
| Entire image visible, allow enlargement | Uniform | Both |
| Fill the header edge to edge, allow cropping (original behavior) | UniformToFill | Both |
| Keep natural size, clip anything outside the header | None | DownOnly (ignored) |

UniformToFill preserves aspect ratio but can zoom/crop small or differently shaped artwork. Fill can distort it. Natural size is measured in WPF device-independent units, using the image's DPI metadata; Windows display scaling still applies. Transparent PNG margins also count toward image size. The banner region clips overflow so cropped artwork stays within the header.

### User-selectable installs and taskbar branding

See [the hotfix 4 guide](HOTFIX4.md) for complete JSON examples, the Enabled/UserSelectable/Required behavior table, dependency handling, persisted declines, -ChooseOptional, and icon setup.

### Step order and dependencies

Steps run in their JSON array order, not numeric ID order. Reordering does not require renaming files. A dependency must point to an earlier enabled step. A disabled dependency is a validation error, so remove/change that reference when disabling a prerequisite.

### Advanced visual changes

Edit `UI/MainWindow.xaml` for corner radii, card spacing, text sizes, the fixed DEVICE SETUP label, status badge layout, error-expander caption, or other strings outside the config. Edit the named resource brushes for light-theme backgrounds. The dark-theme palette is applied by Set-SetupXamlTheme in `Core/Setup.Common.ps1` before the window loads. Keep named controls, resource keys, and binding names intact unless you also update their code references.

The window uses a native Windows frame plus WPF content. Native title-bar appearance follows Windows; selecting the Dark preset changes the content and does not force a dark native frame. The window can be minimized, cannot be maximized, and clamps itself to the desktop work area. Very long text, large banners, or unusually high display scaling may require shorter text or a larger screen.

## Configuration validation

The bundled PowerShell validator checks required properties, branding files, step IDs/count, boolean flags, ranges, dependency order, relative paths, enabled script existence, and exit-code relationships. `Docs/Setup.schema.json` also supplies a JSON Schema for editors and external schema validators. It is a reference file, not a runtime network dependency.
