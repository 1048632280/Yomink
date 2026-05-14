import Foundation

final class ReaderPageCache {
    private let cache = NSCache<NSString, CachedPageByteRange>()

    init(countLimit: Int = 8) {
        cache.countLimit = countLimit
    }

    func page(for key: String) -> PageByteRange? {
        cache.object(forKey: key as NSString)?.page
    }

    func insert(_ page: PageByteRange, for key: String) {
        cache.setObject(CachedPageByteRange(page: page), forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

private final class CachedPageByteRange {
    let page: PageByteRange

    init(page: PageByteRange) {
        self.page = page
    }
}

