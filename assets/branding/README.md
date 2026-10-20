# Triquetra app identity

`triquetra-avatar.png` is the generated master avatar (1254 x 1254, RGBA).
The built-in `image_gen` tool created the artwork. No external API key or CLI
fallback was used. Transparent pixels outside the rounded tile are preserved.

The macOS app icon is in `macOS/Assets.xcassets/AppIcon.appiconset`. Its ten
standard macOS slots cover 16, 32, 128, 256 and 512 points at 1x and 2x, including
a 1024-pixel image. These exports were resized from the master using macOS `sips`.
Xcode compiles the catalog into the application icon for Finder, Dock and alerts.

## Generation prompt

> Use case: logo-brand. Create one finished macOS app icon and reusable avatar for BakaThreesome, inspired by Scandinavian triquetra knotwork. Square 1024x1024 artwork. A single strong, geometrically balanced triquetra: three continuous interwoven rounded leaf-shaped loops, one upward point and two lower points, clear alternating over-under crossings, elegant thick bands and generous negative space so it reads at 32px. Restrained Nordic craftsmanship, polished cool silver knot with subtle bevel and softly lit edges, on a deep charcoal blue-green rounded-square tile, front-facing orthographic view. The knot is centered and occupies approximately 65 percent of the canvas, tile occupies 88 percent; rounded tile corners and a very subtle native macOS-style dimensional edge. Outside the tile is genuinely transparent. Quiet premium native macOS aesthetic, high contrast, clean uncluttered silhouette, balanced symmetrical composition. No text, letters, runes, additional symbols, circle around knot, scenery, objects, elaborate surface patterns or watermark. Deliver the icon itself, not a mockup, with no device or surrounding presentation.
