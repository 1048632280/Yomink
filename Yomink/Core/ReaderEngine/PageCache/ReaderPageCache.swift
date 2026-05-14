import Foundation

final class ReaderPageCache: @unchecked Sendable {
    private let pageRangeCache = NSCache<NSString, CachedPageByteRange>()
    private let readerPageCache = NSCache<NSString, CachedReaderPage>()

    init(countLimit: Int = 8) {
        pageRangeCache.countLimit = countLimit
        readerPageCache.countLimit = countLimit
    }

    func page(for key: String) -> PageByteRange? {
        pageRangeCache.object(forKey: key as NSString)?.page
    }

    func readerPage(for key: String) -> ReaderPage? {
        readerPageCache.object(forKey: key as NSString)?.page
    }

    func insert(_ page: PageByteRange, for key: String) {
        pageRangeCache.setObject(CachedPageByteRange(page: page), forKey: key as NSString)
    }

    func insert(_ page: ReaderPage, for key: String) {
        readerPageCache.setObject(CachedReaderPage(page: page), forKey: key as NSString)
        insert(
            PageByteRange(bookID: page.bookID, pageIndex: page.pageIndex, byteRange: page.byteRange),
            for: key
        )
    }

    func removeAll() {
        pageRangeCache.removeAllObjects()
        readerPageCache.removeAllObjects()
    }
}

private final class CachedReaderPage {
    let page: ReaderPage

    init(page: ReaderPage) {
        self.page = page
    }
}

private final class CachedPageByteRange {
    let page: PageByteRange

    init(page: PageByteRange) {
        self.page = page
    }
}
