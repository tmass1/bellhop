# Valet — icon handoff

Ready-to-use raster macOS icon assets, reconstructed as editable vector geometry from the supplied reference.

## Design

Keep the near-black rounded square (#131315), white U-shaped tray/smile, two circular endpoints, and three nested curves in #777779, #9E9EA0, and #C6C6C8. The subtle edge is #343436. The app artwork has transparent padding and corners; no white reference-image background is baked in. The 1024-unit master uses a 896-unit rounded square with a 208-unit corner radius and 64-unit padding. The mark stays centered with the reference’s generous negative space.

The menu symbol is separately drawn for 18 × 18 points. It keeps the tray, endpoints, and three curves in black, with transparent gaps and background. Small curves are deliberately lighter in weight. It is a template image: AppKit supplies its appearance color. Do not use the dark rounded square in the menu bar.

## Files

- `AppIcon/`: PNGs at 16, 32, 64, 128, 256, 512, 1024, and 2048 pixels square.
- `Assets.xcassets/AppIcon.appiconset/`: ten macOS slots — 16, 32, 128, 256, and 512 points, each at 1× and 2×.
- `Assets.xcassets/ValetMenuTemplate.imageset/`: 18- and 36-pixel PNGs, tagged for template rendering.
- `MenuBar/`: standalone 18-, 36-, and 54-pixel transparent PNGs. The 54-pixel version is supplementary; the macOS catalog uses 1×/2×.
- `Valet.icns` and `Valet.iconset/`: packaged app icon and conventional PNG iconset.
- `Sources/`: editable SVG masters. Render these to regenerate exports; do not enlarge a small PNG.
- `Preview.png`: presentation only; light/dark menu samples show simulated tinting.
- `Reference/user-reference.png`: supplied visual reference.
- `Verification.json`: dimensions, alpha checks, template-color checks, and ICNS representations.
- `SHA256SUMS.txt`: package checksums.

## Integrate in Xcode

Copy the two asset sets into your existing asset catalog (or use the included catalog if the project has none). If an `AppIcon` set already exists, replace its contents. Set the target’s App Icon source to `AppIcon`.

```swift
import AppKit

// Keep the status item strongly retained by your controller.
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
if let button = statusItem.button,
   let source = NSImage(named: "ValetMenuTemplate"),
   let image = source.copy() as? NSImage {
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.toolTip = "Valet"
    button.setAccessibilityLabel("Valet")
}
```

When loading standalone PNGs instead, bundle the base and `@2x` files together and explicitly keep the image size at 18 points. Never display the 36-pixel export at 36 points. Keep black RGB values and alpha intact; do not bake in a white dark-mode version.

These are conventional raster app-icon assets. They are not a layered Icon Composer `.icon` project. A future Icon Composer treatment should start from the SVG geometry and preserve the approved design.

## Verification and final app check

All PNG dimensions, asset-catalog file references, transparency, menu-image black RGB values, and ICNS image dimensions are checked. The contact sheet is visually reviewed at normal and enlarged sizes. This package is not integrated into a running Valet build; check the actual Dock and menu item on the app’s supported macOS versions before release, including selected, light, and dark appearances.

Apple references: [macOS app-icon asset setup](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), [template-image behavior](https://developer.apple.com/documentation/appkit/nsimage/istemplate), [image-set metadata](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/ImageSetType.html).
