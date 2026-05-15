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

    func testReaderPagingServiceBuildsPreviousPageEndingAtCurrentStart() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookRepository(databaseManager: databaseManager)
        let pageCache = ReaderPageCache(countLimit: 3)
        let pagingService = ReaderPagingService(bookRepository: repository, pageCache: pageCache)
        let fileURL = try makeTemporaryTextFile(
            text: String(repeating: "Yomink reverse paging line with CoreText.\n", count: 240)
        )
        let book = BookRecord(
            id: UUID(),
            title: "Reverse Paging",
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
        let firstPageResult = try await pagingService.page(
            ReaderPageRequest(
                bookID: book.id,
                startByteOffset: 0,
                pageIndex: 0,
                layout: layout
            )
        )
        let firstPage = try XCTUnwrap(firstPageResult)
        let secondPageResult = try await pagingService.page(
            ReaderPageRequest(
                bookID: book.id,
                startByteOffset: firstPage.endByteOffset,
                pageIndex: 1,
                layout: layout
            )
        )
        let secondPage = try XCTUnwrap(secondPageResult)

        let previousPageResult = try await pagingService.previousPage(
            ReaderPreviousPageRequest(
                bookID: book.id,
                endByteOffset: secondPage.startByteOffset,
                pageIndex: 0,
                layout: layout
            )
        )
        let previousPage = try XCTUnwrap(previousPageResult)

        XCTAssertEqual(previousPage.endByteOffset, secondPage.startByteOffset)
        XCTAssertEqual(previousPage.startByteOffset, firstPage.startByteOffset)
        XCTAssertEqual(previousPage.text, firstPage.text)
        XCTAssertLessThan(previousPage.startByteOffset, previousPage.endByteOffset)
        XCTAssertFalse(previousPage.text.isEmpty)
    }

    func testReaderPagingServicePagesForwardAfterJumpLoadedPreviousPage() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookRepository(databaseManager: databaseManager)
        let pageCache = ReaderPageCache(countLimit: 6)
        let progressStore = ReadingProgressStore(databaseManager: databaseManager)
        let openingService = ReaderOpeningService(bookRepository: repository, progressStore: progressStore)
        let pagingService = ReaderPagingService(bookRepository: repository, pageCache: pageCache)
        let fileURL = try makeTemporaryTextFile(
            text: String(repeating: "0123456789 Yomink precise jump paging.\n", count: 500)
        )
        let book = BookRecord(
            id: UUID(),
            title: "Jump Paging",
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
        let jumpedResult = try await openingService.openFirstPage(
            ReaderOpeningRequest(
                bookID: book.id,
                viewportSize: layout.viewportSize,
                layout: layout,
                preferredByteOffset: book.fileSize / 2
            )
        )
        let jumpedPage = jumpedResult.page

        let previousPageResult = try await pagingService.previousPage(
            ReaderPreviousPageRequest(
                bookID: book.id,
                endByteOffset: jumpedPage.startByteOffset,
                pageIndex: 0,
                layout: layout
            )
        )
        let previousPage = try XCTUnwrap(previousPageResult)
        let forwardPageResult = try await pagingService.page(
            ReaderPageRequest(
                bookID: book.id,
                startByteOffset: previousPage.endByteOffset,
                pageIndex: 1,
                layout: layout
            )
        )
        let forwardPage = try XCTUnwrap(forwardPageResult)

        XCTAssertEqual(previousPage.endByteOffset, jumpedPage.startByteOffset)
        XCTAssertEqual(forwardPage.startByteOffset, jumpedPage.startByteOffset)
        XCTAssertEqual(forwardPage.endByteOffset, jumpedPage.endByteOffset)
        XCTAssertEqual(forwardPage.text, jumpedPage.text)
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

        cache.removeAll()

        XCTAssertNil(cache.readerPage(for: "page-key"))
        XCTAssertNil(cache.page(for: "page-key"))
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
