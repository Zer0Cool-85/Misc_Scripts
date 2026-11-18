# Supply your custom theme

Place your existing `.theme` file directly in this folder, for example
`Theme/Custom.theme`, then pass `-ThemeFile "Custom.theme"` to the installer.
The exact file is selected; other `.theme` files are not auto-selected.

The provided `Example-ModMed.theme` is optional. It is not your exported theme
and is never used unless you explicitly name it in the install command.

Every file/subfolder inside `Theme` is copied into the installed payload and
then into each initialized user's profile. Put required custom images, cursor
files, icons and sounds in subfolders such as `Assets`.

For portable references to these files, use the exact uppercase token:

```ini
[Theme]
BrandImage=%BRANDINGTHEMEDIR%\Assets\Logo.png

[Control Panel\Desktop]
Wallpaper=%BRANDINGTHEMEDIR%\Assets\YourWallpaper.jpg

[Control Panel\Cursors]
Arrow=%BRANDINGTHEMEDIR%\Assets\Arrow.cur
```

The helper replaces `%BRANDINGTHEMEDIR%` in the per-user theme copy with the
absolute path of that user's copied `Theme` folder. This is a package token,
not a Windows environment variable. It works in both custom-theme modes.
Standard Windows variables such as `%SystemRoot%` remain available to Windows.

Other paths are left as written. Exported references to the author's
`C:\Users\...` profile, network paths, and plain relative paths are not
automatically repaired. Update them to the token above or to valid paths on the
target devices. The package copies dependencies you supply; it does not
download missing files or install third-party visual-style engines.

Default mode replaces the wallpaper with the package's `Wallpaper` image and
removes the theme's slideshow section. Use `-PreserveThemeSettings` to retain
the theme's own wallpaper/slideshow and its other visual settings. The lock
screen remains a separate image from `Lockscreen` in both modes.

Use a Windows-exported `.theme` file (typically UTF-16 with BOM), or save edited
themes as UTF-16/UTF-8 with BOM so Windows PowerShell 5.1 reads non-ASCII names
correctly. `.themepack` and `.deskthemepack` archives are not accepted; extract
the `.theme` and its dependencies first.
