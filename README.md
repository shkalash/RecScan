# RecScan

An iOS receipt scanner. Capture receipts with the camera, keep them in app-private
storage, filter by date, and merge a selection into a single PDF to share.

Personal project. Native Swift and SwiftUI, one dependency.

## Why it exists

Photographing receipts into the camera roll means they get mixed in with everything
else, sync to places you did not intend, and are impossible to hand to an accountant as
a single document. RecScan keeps them in its own container and turns a date range into
one PDF.

The app never touches PhotoKit. There is no photo library usage key in `Info.plist` and
no entitlement for one — receipts go from the camera straight into the app's own
storage and stay there.

## Dependencies

[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT), for archive import and
export. Foundation can *write* a zip — `NSFileCoordinator`'s `.forUploading` option hands
back one — but offers nothing in the other direction, and there is no public unzip. The
alternatives were hand-rolling a ZIP parser or switching the archive to AppleArchive
`.aar`, which would trade away the whole point of the format: that a zip of images and a
JSON file opens on anything, years from now.

`Package.resolved` is committed. This is an app, not a library, so the resolved versions
are part of the build.

## Requirements

- iOS 18.0+
- Xcode 16+ (developed against Xcode 26)
- Swift 6, strict concurrency

## Getting started

```bash
open RecScan.xcodeproj
```

Set your own team under Signing & Capabilities, then build. Running on a physical
device is required to exercise capture — the Simulator has no document camera, and the
scan button disables itself there.

```bash
xcodebuild -project RecScan.xcodeproj -scheme RecScan \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Architecture

Layered, with dependencies pointing one way: views depend on protocols, and the
concrete stores are injected at the app root.

```
RecScan/
├── Models/      Receipt (@Model), ReceiptStore (ModelActor), store protocol
├── Storage/     HEIC encode/decode, file layout, thumbnail cache
├── Capture/     VNDocumentCameraViewController bridge
├── Filtering/   date presets, predicate construction, month grouping
├── Export/      PDF renderer, summary aggregation, layout metrics
├── Views/       SwiftUI screens and view models
└── Support/     constants, formatting, container factory
```

### Decisions worth knowing

**Images are stored by relative path, never a URL.** The app container path changes
across reinstalls, restores and some OS updates, so a persisted absolute URL rots
silently. `Receipt.relativePath` holds `Receipts/<uuid>.heic` and is resolved against
the Documents directory at read time.

**Every model property has a default and every optional stays optional.** That is the
precondition for switching the `ModelConfiguration` to a CloudKit-backed one later
without a schema migration.

**Writes happen on a `ModelActor`, not the main actor.** Importing a multi-page scan
encodes several HEIC images and inserts several rows; doing that on the main actor
drops frames on the capture dismissal.

**Deleting a receipt removes the row and the file in one method.** Splitting those is
how images get orphaned, so `ReceiptStore.delete(receiptsWithIDs:)` is the only
deletion entry point.

**Search reads a denormalised `searchIndex` column.** The natural predicate — date
bounds AND (merchant OR note OR OCR text), each an optional string — expands into a
`PredicateExpressions` tree the Swift type checker cannot resolve in reasonable time.
Collapsing the three optionals into one maintained column makes the predicate three
flat terms.

**The PDF is drawn with `UIGraphicsPDFRenderer`, not PDFKit.** `PDFPage(image:)` gives
a page and nothing else — no header line, no page numbers, no two-up layout. Each page
renders inside its own `autoreleasepool` with its image loaded inside the loop;
preloading them or dropping the pool gets the app jetsammed part-way through a large
export.

**Stored images carry no alpha channel.** `UIGraphicsImageRendererFormat.opaque` does
not reliably produce one, and ImageIO then warns that the discarded channel doubles
decode memory — which lands directly on the export loop. `ImageCodec` renders into an
explicit `CGContext` with `noneSkipLast` instead.

## Testing

Swift Testing, run against the Simulator.

Suites that encode images are nested under `ImagePipelineSuite`, which is `.serialized`.
The Simulator's HEVC encoder is a shared resource with a bounded connection count: six
concurrent `CGImageDestinationFinalize` calls finish in about a tenth of a second each,
while twelve deadlock permanently and hang the whole run. The app never hits this — its
only image writer is a serial actor — but the test suite fans out unless told not to.

## Backup and restore

**Export Archive** writes a zip of the original images plus `manifest.json`. Both halves
stay readable without this app, which a copy of the SwiftData store would not — and a
store copy is a trap besides, since SQLite runs in WAL mode and the `-wal` sidecar
routinely holds newer data than the `.store` itself.

Getting one back onto the phone works three ways: the in-app file picker, dragging it into
the app's folder in Finder (`UIFileSharingEnabled`), or AirDropping it and choosing
RecScan from the share sheet.

### How merging works

Receipts are identified by the `UUID` assigned at capture, which survives export and
import. Deliberately not content-based: two scans of the same paper receipt are two
receipts, and no image comparison should merge them.

| Local state | Result |
|---|---|
| No receipt with this id | inserted |
| Exists, archive is newer | updated |
| Exists, local is same age or newer | skipped |
| Exists but its image file is missing | updated — the image is restored regardless of dates |

So exporting in August, reinstalling, scanning through September and then importing the
August archive restores August alongside September with nothing duplicated. Importing the
same archive twice is a no-op the second time.

## Status

Capture, storage, library, detail editing, filtering, PDF export and archive
import/export are implemented.

Not yet built: OCR autofill and Face ID lock. `Receipt.ocrText` and the PDF's invisible
searchable-text layer are already wired for the first of those.

## Licence

Personal project, all rights reserved.
