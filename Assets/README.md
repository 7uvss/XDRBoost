# App icon

`AppIcon.png` is the 1024×1024 RGBA source artwork. `build.sh` uses the native macOS `sips` and `iconutil` tools to generate the app's `.icns` resource, including standard and Retina sizes.

The artwork was generated with the built-in `imagegen` tool using this prompt:

> Create one production macOS application icon for XDRBoost, a small menu bar display-brightness utility. Square 1024x1024 composition, transparent outside a centered macOS-style rounded-square tile, generous native icon padding. The tile is a rich near-black midnight blue with a very subtle indigo gradient and precise softly rounded corners. Center one bold, beautifully balanced sun glyph: a solid warm amber disc and eight short rounded rays, with a restrained warm yellow-to-orange gradient. Extremely clean geometry, crisp edges, understated depth and no busy effects; should read instantly at 32px. Straight-on orthographic view, not perspective. No text, no letters, no numbers, no border, no mockup, no surrounding objects, no lens flares, no screen or monitor illustration. Deliver only the icon artwork with real alpha transparency outside the tile.
