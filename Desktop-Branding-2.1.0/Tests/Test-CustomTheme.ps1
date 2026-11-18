#requires -Version 5.1
# No installation, registry changes or theme activation. Uses temporary strings.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $packageRoot 'DesktopBranding.Theme.ps1')
$script:passed = 0

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Label)
    if ($Actual -cne $Expected) {
        throw "FAILED: $Label. Expected [$Expected]; actual [$Actual]."
    }
    $script:passed++
}
function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw "FAILED: $Label" }
    $script:passed++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Label)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught -or $caught -notmatch $Pattern) {
        throw "FAILED: $Label. Expected error matching [$Pattern]; received [$caught]."
    }
    $script:passed++
}

$theme = @'
; Custom exported theme
[Theme]
DisplayName=ModMed Custom
BrandImage=%BRANDINGTHEMEDIR%\Assets\Logo.png

[Control Panel\Desktop]
Wallpaper=C:\Users\Author\Pictures\old.jpg
WallpaperStyle=6
TileWallpaper=1

[VisualStyles]
Path=%SystemRoot%\Resources\Themes\Aero\Aero.msstyles
ColorizationColor=0xA1123456
AutoColorization=1
SystemMode=Light
AppMode=Dark
Transparency=1

[Control Panel\Cursors]
Arrow=%BRANDINGTHEMEDIR%\Assets\arrow.cur

[Slideshow]
Interval=1800000
Shuffle=1
ImagesRootPath=%BRANDINGTHEMEDIR%\Assets\Slides

[Sounds]
SchemeName=My custom sound scheme

[MasterThemeSelector]
MTSM=DABJDKT
'@

$generated = Resolve-BrandingThemeSettings
Assert-Equal $generated.ThemeMode 'Generated' 'Default mode remains generated'
Assert-Equal $generated.AccentHex '3F177E' 'Generated mode keeps default purple'
Assert-Equal $generated.AppsUseLightTheme 1 'Generated mode keeps light apps'
$generatedText = New-BrandingThemeText -Settings $generated -WallpaperPath 'C:\Branding\wall.jpg'
Assert-Equal (Get-BrandingThemeSetting $generatedText 'Control Panel\Desktop' 'Wallpaper') 'C:\Branding\wall.jpg' 'Generated wallpaper'
Assert-Equal (Get-BrandingThemeSetting $generatedText 'VisualStyles' 'ColorizationColor') '0xC43F177E' 'Generated ARGB encoding'

$custom = Resolve-BrandingThemeSettings -CustomTheme -ThemeText $theme
Assert-Equal $custom.ThemeMode 'CustomBranding' 'Custom file selects branding mode'
Assert-Equal $custom.AccentHex '123456' 'Omitted AccentHex inherits custom RGB'
Assert-Equal $custom.DwmAlpha 161 'Custom ARGB alpha is retained'
Assert-Equal $custom.AppsUseLightTheme 0 'Custom dark app mode is retained'
Assert-Equal $custom.WallpaperStyle '6' 'Wallpaper fit style is retained'
Assert-Equal $custom.TileWallpaper '1' 'Wallpaper tiling is retained'

$wallpaper = 'C:\Users\test$1\Pictures\Corporate wallpaper.jpg'
$assets = 'C:\Users\test$1\AppData\Local\ModMed\Theme'
$rewritten = New-BrandingThemeText -Settings $custom -ThemeText $theme -WallpaperPath $wallpaper -ThemeAssetsPath $assets
Assert-Equal (Get-BrandingThemeSetting $rewritten 'Theme' 'DisplayName') 'ModMed Custom' 'Theme name preserved'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'Control Panel\Desktop' 'Wallpaper') $wallpaper 'Literal wallpaper path with dollar and spaces'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'Control Panel\Desktop' 'WallpaperStyle') '6' 'Fit is not changed to Fill'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'VisualStyles' 'ColorizationColor') '0xA1123456' 'Custom RGB/alpha written to copied theme'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'VisualStyles' 'SystemMode') 'Dark' 'Shell dark mode for Start/taskbar accent'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'VisualStyles' 'AppMode') 'Dark' 'No unwanted light app mode override'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'VisualStyles' 'AutoColorization') '0' 'Manual custom accent'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'VisualStyles' 'Transparency') '1' 'Unrelated transparency setting retained'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'Sounds' 'SchemeName') 'My custom sound scheme' 'Sounds retained'
Assert-Equal (Get-BrandingThemeSetting $rewritten 'Control Panel\Cursors' 'Arrow') ($assets + '\Assets\arrow.cur') 'Theme resource token is literal'
Assert-True ($rewritten -notmatch '(?im)^\[Slideshow\]') 'Managed picture removes slideshow only'
Assert-True ($theme -match '(?im)^\[Slideshow\]') 'Input theme string was not mutated'

$override = Resolve-BrandingThemeSettings -CustomTheme -ThemeText $theme -AccentHex '#ABCDEF' -AccentWasSpecified
$overrideText = New-BrandingThemeText -Settings $override -ThemeText $theme -WallpaperPath $wallpaper -ThemeAssetsPath $assets
Assert-Equal $override.AccentHex 'ABCDEF' 'Explicit color wins'
Assert-Equal (Get-BrandingThemeSetting $overrideText 'VisualStyles' 'ColorizationColor') '0xA1ABCDEF' 'Override updates RGB and preserves source alpha'

$preserve = Resolve-BrandingThemeSettings -CustomTheme -ThemeText $theme -PreserveThemeSettings
$preservedText = New-BrandingThemeText -Settings $preserve -ThemeText $theme -ThemeAssetsPath $assets
Assert-Equal $preserve.ThemeMode 'CustomPreserve' 'Preserve mode selected'
Assert-True ($null -eq $preserve.AccentHex) 'Preserve mode does not manufacture an accent override'
Assert-Equal $preservedText ($theme.Replace('%BRANDINGTHEMEDIR%', $assets)) 'Preserve mode changes only documented resource token'
Assert-Equal (Get-BrandingThemeSetting $preservedText 'VisualStyles' 'SystemMode') 'Light' 'Preserve mode leaves light shell'
Assert-True ($preservedText -match '(?im)^\[Slideshow\]') 'Preserve mode retains slideshow'

$noColor = Set-BrandingThemeSetting $theme 'VisualStyles' 'ColorizationColor' ''
Assert-Throws { Resolve-BrandingThemeSettings -CustomTheme -ThemeText $noColor } 'ColorizationColor' 'Missing color does not silently fall back'
$noColorOverride = Resolve-BrandingThemeSettings -CustomTheme -ThemeText $noColor -AccentHex '#654321' -AccentWasSpecified
Assert-Equal $noColorOverride.AccentHex '654321' 'Explicit override supports theme without fixed color'
$noAppMode = Set-BrandingThemeSetting $theme 'VisualStyles' 'AppMode' ''
Assert-True ($null -eq (Resolve-BrandingThemeSettings -CustomTheme -ThemeText $noAppMode).AppsUseLightTheme) 'Missing app mode does not force light'
Assert-Throws { Resolve-BrandingThemeSettings -PreserveThemeSettings } 'requires' 'Preserve requires custom theme'
Assert-Throws { Resolve-BrandingThemeSettings -CustomTheme -ThemeText $theme -PreserveThemeSettings -AccentWasSpecified } 'conflicts' 'Contradictory preserve/color options fail'
Assert-Throws { Resolve-BrandingThemeSettings -CustomTheme -ThemeText '[Theme]' } 'missing' 'Malformed theme is rejected'
$badTag = Set-BrandingThemeSetting $theme 'MasterThemeSelector' 'MTSM' 'invalid'
Assert-Throws { Resolve-BrandingThemeSettings -CustomTheme -ThemeText $badTag } 'MTSM' 'Invalid master tag rejected'
$contrast = Set-BrandingThemeSetting $theme 'VisualStyles' 'Path' ''
Assert-Throws { Resolve-BrandingThemeSettings -CustomTheme -ThemeText $contrast } 'PreserveThemeSettings' 'Contrast/classic theme needs preserve mode'
Assert-Equal (Resolve-BrandingThemeSettings -CustomTheme -ThemeText $contrast -PreserveThemeSettings).ThemeMode 'CustomPreserve' 'Contrast/classic accepted with preservation'

$duplicates = "[visualstyles]`ncolorizationcolor=0xAA111111`nColorizationColor=0xBB222222`n[Sounds]`nSchemeName=Keep"
Assert-Equal (Get-BrandingThemeSetting $duplicates 'VisualStyles' 'ColorizationColor') '0xBB222222' 'Case-insensitive last key read'
$deduped = Set-BrandingThemeSetting $duplicates 'VisualStyles' 'ColorizationColor' '0xCC333333'
Assert-Equal (Get-BrandingThemeSetting $deduped 'VisualStyles' 'ColorizationColor') '0xCC333333' 'Duplicate keys rewritten consistently'
Assert-Equal (Get-BrandingThemeSetting $deduped 'Sounds' 'SchemeName') 'Keep' 'Adjacent section not changed'
$added = Set-BrandingThemeSetting '[Theme]' 'VisualStyles' 'SystemMode' 'Dark'
Assert-Equal (Get-BrandingThemeSetting $added 'VisualStyles' 'SystemMode') 'Dark' 'Missing section inserted'
$addedKey = Set-BrandingThemeSetting "[Theme]`nDisplayName=Hello`n[Sounds]`nSchemeName=Keep" 'Theme' 'BrandImage' 'C:\logo.png'
Assert-Equal (Get-BrandingThemeSetting $addedKey 'Theme' 'BrandImage') 'C:\logo.png' 'Missing key inserted before next section'

Get-ChildItem -LiteralPath $packageRoot -Filter '*.ps1' -Recurse | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count) {
        throw "PowerShell parser error in $($_.Name): $($parseErrors | Out-String)"
    }
    $script:passed++
}
Write-Output "PASS: $script:passed assertions/parser checks; PowerShell $($PSVersionTable.PSVersion). No Windows desktop changes executed."
