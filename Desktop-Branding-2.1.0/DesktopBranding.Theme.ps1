#requires -Version 5.1
# Pure theme parsing/transformation helpers. No registry, UI or task mutations.

function Get-BrandingThemeSetting {
    param([AllowEmptyString()][string]$Text, [string]$Section, [string]$Name)
    $inside = $false
    $value = $null
    foreach ($line in ($Text -split '\r\n|\n|\r')) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $inside = $Matches[1].Trim() -ieq $Section
        }
        elseif ($inside -and $line -match '^\s*([^;#=][^=]*?)\s*=(.*)$') {
            if ($Matches[1].Trim() -ieq $Name) { $value = $Matches[2].Trim() }
        }
    }
    return $value
}

function Set-BrandingThemeSetting {
    param([AllowEmptyString()][string]$Text, [string]$Section,
          [string]$Name, [AllowEmptyString()][string]$Value)
    $lines = [Collections.Generic.List[string]]::new()
    $inside = $false
    $foundSection = $false
    $foundKey = $false
    foreach ($line in ($Text -split '\r\n|\n|\r')) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            if ($inside -and -not $foundKey) {
                $lines.Add("$Name=$Value")
                $foundKey = $true
            }
            $inside = $Matches[1].Trim() -ieq $Section
            if ($inside) { $foundSection = $true }
            $lines.Add($line)
        }
        elseif ($inside -and $line -match '^\s*([^;#=][^=]*?)\s*=(.*)$' -and
                $Matches[1].Trim() -ieq $Name) {
            $lines.Add("$Name=$Value")
            $foundKey = $true
        }
        else { $lines.Add($line) }
    }
    if (-not $foundSection) {
        $lines.Add('')
        $lines.Add("[$Section]")
        $lines.Add("$Name=$Value")
    }
    elseif (-not $foundKey) { $lines.Add("$Name=$Value") }
    return ($lines -join "`r`n")
}

function Remove-BrandingThemeSection {
    param([AllowEmptyString()][string]$Text, [string]$Section)
    $skip = $false
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split '\r\n|\n|\r')) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $skip = $Matches[1].Trim() -ieq $Section
        }
        if (-not $skip) { $lines.Add($line) }
    }
    return ($lines -join "`r`n")
}

function Resolve-BrandingThemeSettings {
    param(
        [AllowEmptyString()][string]$ThemeText = '',
        [string]$CompanyFolder = 'ModMed',
        [string]$AccentHex = '#3F177E',
        [switch]$CustomTheme,
        [switch]$AccentWasSpecified,
        [switch]$PreserveThemeSettings
    )
    if ($PreserveThemeSettings -and -not $CustomTheme) {
        throw '-PreserveThemeSettings requires -ThemeFile.'
    }
    if ($PreserveThemeSettings -and $AccentWasSpecified) {
        throw '-AccentHex conflicts with -PreserveThemeSettings.'
    }
    $result = [ordered]@{
        ThemeMode = 'Generated'
        ThemeDisplayName = $CompanyFolder
        AccentHex = $AccentHex.TrimStart('#').ToUpperInvariant()
        DwmAlpha = 196
        AppsUseLightTheme = 1
        WallpaperStyle = '10'
        TileWallpaper = '0'
    }
    if (-not $CustomTheme) { return [pscustomobject]$result }

    foreach ($section in @('Control Panel\Desktop', 'VisualStyles', 'MasterThemeSelector')) {
        $pattern = '(?im)^\s*\[{0}\]\s*$' -f [regex]::Escape($section)
        if ($ThemeText -notmatch $pattern) { throw "Custom theme is missing [$section]." }
    }
    if ((Get-BrandingThemeSetting $ThemeText 'MasterThemeSelector' 'MTSM') -ine 'DABJDKT') {
        throw 'Custom theme requires [MasterThemeSelector] MTSM=DABJDKT.'
    }
    $displayName = Get-BrandingThemeSetting $ThemeText 'Theme' 'DisplayName'
    if ($displayName) { $result.ThemeDisplayName = $displayName }

    if ($PreserveThemeSettings) {
        $result.ThemeMode = 'CustomPreserve'
        $result.ThemeDisplayName = $displayName
        $result.AccentHex = $null
        $result.DwmAlpha = $null
        $result.AppsUseLightTheme = $null
        $result.WallpaperStyle = $null
        $result.TileWallpaper = $null
        return [pscustomobject]$result
    }
    $result.ThemeMode = 'CustomBranding'
    if ([string]::IsNullOrWhiteSpace(
        (Get-BrandingThemeSetting $ThemeText 'VisualStyles' 'Path')
    )) {
        throw 'Custom branding requires a visual-style Path. Use -PreserveThemeSettings for a contrast/classic theme.'
    }
    $color = Get-BrandingThemeSetting $ThemeText 'VisualStyles' 'ColorizationColor'
    $validColor = $false
    if ($color -match '^0x([0-9a-f]{2})([0-9a-f]{6})$') {
        $result.DwmAlpha = [Convert]::ToInt32($Matches[1], 16)
        if (-not $AccentWasSpecified) { $result.AccentHex = $Matches[2].ToUpperInvariant() }
        $validColor = $true
    }
    if (-not $AccentWasSpecified -and -not $validColor) {
        throw 'Custom theme needs ColorizationColor=0xAARRGGBB under [VisualStyles], or supply -AccentHex, or use -PreserveThemeSettings.'
    }
    $style = Get-BrandingThemeSetting $ThemeText 'Control Panel\Desktop' 'WallpaperStyle'
    $tile = Get-BrandingThemeSetting $ThemeText 'Control Panel\Desktop' 'TileWallpaper'
    if ($null -ne $style) {
        if ($style -notmatch '^\d+$') { throw 'Theme WallpaperStyle must be numeric.' }
        $result.WallpaperStyle = $style
    }
    if ($null -ne $tile) {
        if ($tile -notmatch '^[01]$') { throw 'Theme TileWallpaper must be 0 or 1.' }
        $result.TileWallpaper = $tile
    }
    $appMode = Get-BrandingThemeSetting $ThemeText 'VisualStyles' 'AppMode'
    $result.AppsUseLightTheme = $null
    if ($appMode -ieq 'Light') { $result.AppsUseLightTheme = 1 }
    elseif ($appMode -ieq 'Dark') { $result.AppsUseLightTheme = 0 }
    return [pscustomobject]$result
}

function New-BrandingThemeText {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [AllowEmptyString()][string]$ThemeText = '',
        [AllowEmptyString()][string]$WallpaperPath = '',
        [AllowEmptyString()][string]$ThemeAssetsPath = ''
    )
    if ($Settings.ThemeMode -eq 'CustomPreserve') {
        # Only this documented deployment token is substituted. Ordinary
        # Windows environment variables are left for Windows to expand.
        return $ThemeText.Replace('%BRANDINGTHEMEDIR%', $ThemeAssetsPath)
    }
    $color = '0x{0:X2}{1}' -f [int]$Settings.DwmAlpha, $Settings.AccentHex
    if ($Settings.ThemeMode -eq 'Generated') {
        return @"
[Theme]
DisplayName=$($Settings.ThemeDisplayName)

[Control Panel\Desktop]
Wallpaper=$WallpaperPath
TileWallpaper=$($Settings.TileWallpaper)
WallpaperStyle=$($Settings.WallpaperStyle)

[VisualStyles]
Path=%SystemRoot%\Resources\Themes\Aero\Aero.msstyles
ColorStyle=NormalColor
Size=NormalSize
ColorizationColor=$color
AutoColorization=0
SystemMode=Dark
AppMode=Light

[MasterThemeSelector]
MTSM=DABJDKT
"@
    }
    if ($Settings.ThemeMode -ne 'CustomBranding') { throw 'Unknown theme mode.' }
    $text = $ThemeText.Replace('%BRANDINGTHEMEDIR%', $ThemeAssetsPath)
    # A package-managed picture replaces any slideshow in this mode.
    $text = Remove-BrandingThemeSection $text 'Slideshow'
    $text = Set-BrandingThemeSetting $text 'Control Panel\Desktop' 'Wallpaper' $WallpaperPath
    $text = Set-BrandingThemeSetting $text 'Control Panel\Desktop' 'WallpaperStyle' $Settings.WallpaperStyle
    $text = Set-BrandingThemeSetting $text 'Control Panel\Desktop' 'TileWallpaper' $Settings.TileWallpaper
    $text = Set-BrandingThemeSetting $text 'VisualStyles' 'ColorizationColor' $color
    $text = Set-BrandingThemeSetting $text 'VisualStyles' 'AutoColorization' '0'
    $text = Set-BrandingThemeSetting $text 'VisualStyles' 'SystemMode' 'Dark'
    if (-not (Get-BrandingThemeSetting $text 'Theme' 'DisplayName')) {
        $text = Set-BrandingThemeSetting $text 'Theme' 'DisplayName' $Settings.ThemeDisplayName
    }
    return $text
}
