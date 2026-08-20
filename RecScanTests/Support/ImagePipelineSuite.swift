import Testing

/// Parent suite for every test that encodes a receipt image.
///
/// Responsibilities:
/// - Force all image-encoding tests to run one at a time.
///
/// ## Why serialisation is required
/// The iOS Simulator's HEVC encoder is a shared resource with a bounded number of
/// connections. Six concurrent `CGImageDestinationFinalize` calls complete in about a
/// tenth of a second each; twelve deadlock permanently, and the whole test run hangs
/// with every thread parked inside `ImageCodec.encodeHEIC`.
///
/// The app itself is unaffected — `ReceiptStore` is a serial actor and is the only
/// caller that writes images, so production never issues concurrent encodes. It is the
/// test suite that fans out, by calling the storage layer directly from many tests at
/// once. Nesting those suites here restores the serialisation the app has by design.
///
/// `.serialized` applies to this suite and everything nested beneath it.
@Suite("Image pipeline", .serialized)
enum ImagePipelineSuite {}
