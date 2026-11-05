# Hotfix 6: IsSelected startup error

The enterprise JSON is valid without an IsSelected field. IsSelected is a property
on the UI's compiled C# StepViewModel, not a configuration setting. Every step,
including automatic steps, initializes that property.

The earlier startup code reused any DeviceSetupUI.StepViewModel already loaded
in the current PowerShell process. If an older release had been run in the same
ISE/PowerShell host, that cached class could lack the optional-selection properties.
An older UI/StepViewModel.cs file mixed with newer PowerShell files could produce
the same missing-property symptom. Without the original error's script location,
these are supported causes, not proof of which occurred on a particular device.

Hotfix 6 loads the model under a namespace derived from its source hash, so a
different source revision cannot reuse the earlier class. It also validates the
selection properties before constructing the window. Old model files now produce
a specific version-mismatch message identifying the files to update.

## Install the fix

Prefer extracting the complete ZIP to a **new folder**, then copying your company
configuration, branding and custom step scripts into it. For an in-place upgrade
from hotfix 5, replace these together:

- Start-DeviceSetup.ps1
- Core/Setup.Common.ps1
- UI/StepViewModel.cs
- UI/MainWindow.xaml (merge your layout changes if customized)

The C# and XAML contents have not changed from hotfix 5; copying them ensures an
older file is not accidentally retained. Keep UI/TaskbarIdentity.cs from hotfix 4
or later. Enterprise scripts and JSON are unchanged. No completion-state reset
or SetupVersion bump is required for this framework-only fix.

Close the previous setup window and launch Run-Enterprise-Demo.cmd from the new
folder. It starts a fresh PowerShell process and runs no installers. Once the
demo starts successfully, use your existing SYSTEM + ServiceUI live launcher
pointing to the same updated folder/configuration.

If the error still occurs, capture the complete message and script line/stack
trace, plus whether it occurs before the window opens or after Start/Retry. This
distinguishes a different object problem from a mismatched/cached UI model.

## Validation

Static syntax, configuration, XAML/binding and package checks were run. Windows
runtime execution is unavailable in the build environment. The updated Windows
smoke suite includes cached legacy model, changed-source reload, mismatched-file
diagnostics, and all-five-automatic-step enterprise initialization cases. These
Windows regression tests are supplied but have not been executed here.
