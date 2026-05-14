import CoreGraphics
import XCTest
@testable import Yomink

final class ReaderPagingServiceTests: XCTestCase {
    func testReaderPagingServiceBuildsNextPageFromPreviousByteOffset() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookRepository(databaseManager: databaseManager)
        let pageCache = ReaderPageCache(countLimit: 3)
        let pagingService = ReaderPagingService(bookRepository: repository, pageCache: pageCache)
        let fileURL = try makeTemporaryTextFile(
            text: String(repeating: "Yomink paging line with CoreText.\n", count: 200)
        )
        let book = BookRecord(
            id: UUID(),
            title: "Paging",
            author: nil,
            filePath: fileURL.path,
            encoding: .utf8,
            fileSize: (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0,
            importedAt: Date(),
            lastReadAt: nil
        )
        _ = try repository.insertImportedBook(book)

        var layout = ReadingLayout.defaultPhone
        layout.viewportSize = CGSize(width: 180, height: 160)
        let firstPage = try await pagingService.page(
            ReaderPageRequest(
                bookID: book.id,
                startByteOffset: 0,
                pageIndex: 0,
                layout: layout
            )
        )
        let unwrappedFirstPage = try XCTUnwrap(firstPage)
        let secondPage = try await pagingService.page(
            ReaderPageRequest(
                bookID: book.id,
                startByteOffset: unwrappedFirstPage.endByteOffset,
                pageIndex: 1,
                layout: layout
            )
        )
        let unwrappedSecondPage = try XCTUnwrap(secondPage)

        XCTAssertEqual(unwrappedFirstPage.startByteOffset, 0)
        XCTAssertEqual(unwrappedSecondPage.pageIndex, 1)
        XCTAssertEqual(unwrappedSecondPage.startByteOffset, unwrappedFirstPage.endByteOffset)
        XCTAssertGreaterThan(unwrappedSecondPage.endByteOffset, unwrappedSecondPage.startByteOffset)
    }

    func testReaderPageCacheStoresLightweightReaderPage() {
        let cache = ReaderPageCache(countLimit: 2)
        let page = ReaderPage(
            bookID: UUID(),
            pageIndex: 2,
            byteRange: UInt64(128)..<UInt64(256),
            text: "cached page"
        )

        cache.insert(page, for: "page-key")

        XCTAssertEqual(cache.readerPage(for: "page-key"), page)
        XCTAssertEqual(cache.page(for: "page-key")?.byteRange, UInt64(128)..<UInt64(256))
    }

    private func makeTemporaryTextFile(text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("paging.txt")
        try Data(text.utf8).write(to: fileURL)
        return fileURL
    }
}
