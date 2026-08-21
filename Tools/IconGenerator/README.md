# Icon generator

Draws the RecScan app icon candidates as 1024×1024 PNGs using Core Graphics.

Deliberately kept outside `RecScan/`. That directory is a synchronized folder group,
so every `.swift` file inside it is compiled into the app target automatically — this
script must not be.

## Running

```bash
swift Tools/IconGenerator/GenerateIcons.swift /tmp/recscan-icons
```

Output lands in the directory you pass. `out/` next to this file is gitignored, so
running it from here is also safe.

## Installing a different icon

```bash
cp /tmp/recscan-icons/10-merge.png RecScan/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

The catalog references `AppIcon.png` by name, so replacing that one file is the whole
job. Rebuild and Xcode derives every device size from it.

## Constraints worth preserving

Icons are drawn full-bleed with **no alpha channel** and **no rounded corners**. iOS
applies its own mask; baking one in produces a visible double-rounded edge, and an
alpha channel gets an App Store submission rejected.

The current icon is `10-merge` — two receipts converging into one sheet.
