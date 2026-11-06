# Your branding assets

Put your logo and/or banner here and configure their relative paths in Config/Setup.json.

- Logo: PNG with transparency is preferred. Suggested source size: 600 x 160 pixels.
- Banner: JPG or PNG. A wide image such as 1800 x 240 pixels suits the header; smaller images are also supported.
- PNG, JPG, JPEG, and BMP are supported. SVG is not loaded directly by this WPF package.
- LogoPath and BannerPath can both be set, or both left empty.
- The logo fits proportionally within LogoMaxWidth and LogoMaxHeight.
- The banner defaults to Uniform + DownOnly: the entire image fits proportionally, larger images shrink, and smaller images are not enlarged. It is centered over the main window background (CanvasBrush).
- For the original edge-to-edge appearance, set BannerStretch to UniformToFill and BannerStretchDirection to Both. This may enlarge/crop the artwork; keep text/logos away from edges.
- BannerHeight controls the fixed header region. Natural image size uses WPF units and the file's DPI metadata; Windows display scaling still applies.
- Image files are loaded from disk, not from the network. Paths are package-relative.

Example:

    "LogoPath": "Assets/company-logo.png",
    "BannerPath": "Assets/company-banner.jpg",
    "BannerHeight": 110,
    "BannerStretch": "Uniform",
    "BannerStretchDirection": "DownOnly"

An empty image path hides that image. CompanyName and the welcome text still appear.

## Window icon

The built-in blue setup icon needs no asset file. Set Branding.IconPath to a package-relative ICO or PNG for your own icon, for example Assets/company-setup.ico. Prefer square artwork and an ICO with 16/32/48/256 pixel variants. This setting is independent of LogoPath and BannerPath. An empty string uses the built-in icon.
