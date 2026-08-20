import Foundation
import UIKit

/// In-memory cache of grid thumbnails, keyed by receipt identifier.
///
/// Responsibilities:
/// - Avoid re-decoding a thumbnail every time a cell scrolls back into view.
/// - Drop its contents under memory pressure.
///
/// Why `@unchecked Sendable`: `NSCache` is documented as thread-safe, but it predates
/// `Sendable` and carries no annotation. The only stored property is the cache itself
/// and it is never reassigned, so the unchecked conformance is sound.
final class ThumbnailCache: @unchecked Sendable {

    private let cache: NSCache<NSUUID, UIImage>

    init(countLimit: Int = StorageConstants.thumbnailCacheCountLimit) {
        cache = NSCache<NSUUID, UIImage>()
        cache.countLimit = countLimit
    }

    func image(for id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    func store(_ image: UIImage, for id: UUID) {
        cache.setObject(image, forKey: id as NSUUID)
    }

    func removeImage(for id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
