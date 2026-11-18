# Desktop Branding 2.1.0

- Added `-ThemeFile` to select an exact `.theme` file from the package `Theme` folder.
- Added `-PreserveThemeSettings` to keep the custom theme visual settings and apply only the separate lock-screen step afterward.
- Default custom mode keeps unrelated theme sections, uses the packaged wallpaper, and reads the theme accent unless `-AccentHex` was explicitly supplied.
- Preserves the custom theme wallpaper placement, ARGB alpha and app mode in default custom mode. Dark Windows mode and Start/taskbar accent remain enabled in that mode.
- Copies custom dependencies into the user profile; supports `%BRANDINGTHEMEDIR%` references.
- Adds theme validation, payload-aware detection, an optional example, documentation, and regression tests.
- Keeps `Defaults-v2` as the default completion identity. Existing completed users are not reset by the upgrade alone; choose a new DefaultsId deliberately when applying a new theme to them.

The deployment folder, task names and registry namespace remain `DesktopBrandingV2` for upgrade continuity. Use the included 2.1.0 detection script when uploading the updated Win32 package.
