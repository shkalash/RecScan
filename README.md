# RecScan

An iOS receipt scanner. Capture receipts with the camera, keep them in app-private
storage, sort them into categories, and merge a selection into a single PDF to share —
with a per-category expense breakdown for a date range.

Personal project. Native Swift and SwiftUI, one dependency.

## Why it exists

Photographing receipts into the camera roll means they get mixed in with everything
else, sync to places you did not intend, and are impossible to hand to an accountant as
a single document. RecScan keeps them in its own container and turns a date range into
one PDF.

The app never touches PhotoKit. There is no photo library usage key in `Info.plist` and
no entitlement for one, even though importing from Photos is supported: `PhotosPicker`
runs out of process and hands back only what was picked, so there is nothing to ask
permission for. Whichever route a receipt arrives by, it lands in the app's own storage
and stays there.

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
├── Models/      Receipt and ReceiptCategory (@Model), ReceiptStore (ModelActor), protocols
├── Storage/     HEIC encode/decode, file layout, thumbnail cache
├── Capture/     VNDocumentCameraViewController bridge
├── Import/      Photos/Files/PDF readers, EXIF dates, share-extension inbox, coalescing queue
├── OCR/         Vision text recognition, amount parsing, serial queue
├── Filtering/   date presets, predicate construction, month grouping
├── Export/      PDF renderer, summary aggregation, category report, layout metrics
├── Archive/     zip export, import, manifest, merge policy
├── Views/       SwiftUI screens and view models
└── Support/     constants, formatting, settings, container factory

ShareExtension/  receives receipts from other apps' share sheets
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

**Filters carry a "match everything" value so the predicate keeps a fixed shape.** One
literal per combination of active filters doubles with every filter added. Sentinels avoid
that — but only where they actually work, which had to be measured rather than assumed:
a `distantPast ..< distantFuture` range matches everything, an "any category" flag matches
everything, and `searchIndex.contains("")` matches **nothing**. Swift's `contains("")` is
true, but SwiftData translates it to a store `CONTAINS`, where an empty operand matches no
rows. So text — and only text — needs a branch, which is what keeps this at two literals
rather than eight.

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

Swift Testing, run against the Simulator. 233 tests in 29 suites.

Suites that encode images are nested under `ImagePipelineSuite`, which is `.serialized`.
The Simulator's HEVC encoder is a shared resource with a bounded connection count: six
concurrent `CGImageDestinationFinalize` calls finish in about a tenth of a second each,
while twelve deadlock permanently and hang the whole run. The app never hits this — its
only image writer is a serial actor — but the test suite fans out unless told not to.

Every view has a `#Preview`, and previews render **real content, never empty state** — a
view that loads images or rows from a store draws placeholder boxes when the fixture is
empty, which is the one state a layout cannot be judged from and which fails silently.
`PreviewFixture` is the single shared source: synchronous (preview bodies are not async)
and deterministic (no `random`, or the canvas reshuffles on every re-render). It is shared
with the Simulator seeding path so the canvas and a running build show the same thing.

Fixtures are wrapped in `#if DEBUG`, so a **Release** build is the check that matters —
a debug-only fixture referenced from an unguarded `#Preview` breaks shipping builds.

## Getting receipts in

Four routes, all landing in the same review sheet:

- **Scan** with the document camera (device only — the Simulator has none)
- **Import from Photos** — multi-select, out-of-process, so there is still no photo
  library permission prompt
- **Import Files** — images and PDFs, multi-select
- **Share to RecScan** from any other app, via the share extension

A PDF becomes one receipt per page, sharing a group the way a multi-page scan does, and
its embedded text goes straight into `ocrText` — for an e-receipt that is real text, and
better than OCR over a picture of it.

Capture dates come from EXIF, then the file's creation date, then today. Only the last is
treated as a guess, and only a guess flags the receipt for review — importing photos that
all carry EXIF leaves nothing needing attention.

However many items arrive and by whatever route, they coalesce into **one** review sheet —
a single scrolling form with a shared date and category, rather than a modal per file.
Dismissing it loses nothing: the receipts are already stored, and their review flag stays
set so the library keeps showing which ones still want attention.

## Reading the amount

Scanned images go through Vision and the numbers are parsed out: the largest becomes the
amount, the rest are offered as one-tap chips.

Nothing about this is language-aware, which is what makes it work. Vision **does not
support Hebrew** at any revision — Hebrew words come back as Latin nonsense (`n7H`,
`naaa`). The digits, though, are read perfectly at full confidence, because digits are
digits in every script. So recognition runs `en-US` with language correction off, and only
the numbers are used.

The decimal separator is decided by **shape, not locale**: the last separator followed by
exactly two digits is the decimal point. `1.234,56` and `1,234.56` both give 1234.56. A
receipt does not say which convention it used, and `Locale.current` would get a German
receipt wrong on an English phone.

**Why the alternatives are shown rather than just the best guess.** "Largest wins" is right
on an ordinary receipt and wrong when a bigger number appears — a pre-discount subtotal,
cash tendered. Recognition can also corrupt a value outright: `₪52.30` has been observed
reading as `152.30`, which is entirely plausible on its own and undetectable in code.
Seeing `52.30` in the chips beside it is the only thing that makes either case fixable.

**Suggestions live in the form, never the database.** They commit on save like any other
field, so no unconfirmed number can reach a total, an export or the report. A guess never
overwrites an amount already on the receipt, never overwrites what has been typed, and
never re-fills a field that was deliberately cleared.

Recognition is queued serially and runs behind the review sheet, which fills in as each
result lands. It outlives the sheet, so dismissing a large batch with "Later" still leaves
every receipt searchable. PDF imports skip it entirely — their embedded text is real text
and strictly better.

## Organising and finding

Categories are user-defined and created inline from the picker, so filing a receipt does
not mean a detour into Settings first. Deleting a category keeps its receipts and leaves
them uncategorised.

The library filters on date range, free text, any combination of categories, and a
"needs review" toggle; unreviewed receipts also carry a badge on their grid tile. Settings
holds the default currency and the category list.

## Reports

A per-category expense breakdown for any date range, viewable in the app and included in
the exported PDF (`ExportOptions.includeCategoryBreakdown`).

It belongs to the **export**, not the archive. An archive is a backup — a faithful copy of
what was captured — and a derived summary in it would be a second source of truth that goes
stale the moment a receipt is edited.

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

Implemented: capture, storage, library, detail editing, categories, filtering, the review
sheet, import from Photos/Files/share sheet, OCR amount suggestions, PDF export, the
category report, and archive import/export.

Not yet built: Face ID lock.

Worth re-running the Vision language probe on each OS bump: if Hebrew recognition ever
lands, anchoring the total to a keyword becomes possible and amount detection gets
meaningfully better.

### Share extension

Needs an App Group, which a free Personal Team **can** provision — verified by reading the
entitlement back out of a signed build rather than trusting the documentation. The group
identifier appears in four places (both entitlements files, `SharedInbox`, and the
extension's controller) and they must be changed together.

## Licence

Personal project, all rights reserved.
