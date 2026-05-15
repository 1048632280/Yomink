import XCTest
@testable import Yomink

final class BookmarkRepositoryTests: XCTestCase {
    func testBookmarkRepositoryStoresBookmarksByByteOffset() throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookmarkRepository(databaseManager: databaseManager)
        let bookID = UUID()
        let laterBookmark = ReadingBookmark(
            bookID: bookID,
            title: "Later",
            byteOffset: 512,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let earlierBookmark = ReadingBookmark(
            bookID: bookID,
            title: "Earlier",
            byteOffset: 128,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        _ = try repository.insert(laterBookmark)
        _ = try repository.insert(earlierBookmark)

        let bookmarks = try repository.fetchBookmarks(bookID: bookID)

        XCTAssertEqual(bookmarks.map(\.title), ["Earlier", "Later"])
        XCTAssertEqual(bookmarks.map(\.byteOffset), [128, 512])
    }

    func testBookmarkServiceUsesCurrentPageStartByteOffset() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookmarkRepository(databaseManager: databaseManager)
        let service = ReadingBookmarkService(repository: repository)
        let bookID = UUID()
        let page = ReaderPage(
            bookID: bookID,
            pageIndex: 3,
            byteRange: 4_096..<4_512,
            text: "Chapter One\nYomink bookmark text"
        )

        let result = try await service.addBookmark(bookID: bookID, page: page)
        let bookmark = result.bookmark
        let bookmarks = try await service.bookmarks(bookID: bookID)

        XCTAssertTrue(result.didCreate)
        XCTAssertEqual(bookmark.byteOffset, page.startByteOffset)
        XCTAssertEqual(bookmark.title, "Chapter One")
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.id, bookmark.id)
        XCTAssertEqual(bookmarks.first?.byteOffset, page.startByteOffset)
    }

    func testBookmarkServiceReusesExistingBookmarkAtSameByteOffset() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookmarkRepository(databaseManager: databaseManager)
        let service = ReadingBookmarkService(repository: repository)
        let bookID = UUID()
        let page = ReaderPage(
            bookID: bookID,
            pageIndex: 5,
            byteRange: 8_192..<8_640,
            text: "Duplicated Bookmark\nBody"
        )

        let firstResult = try await service.addBookmark(bookID: bookID, page: page)
        let secondResult = try await service.addBookmark(bookID: bookID, page: page)
        let bookmarks = try await service.bookmarks(bookID: bookID)

        XCTAssertTrue(firstResult.didCreate)
        XCTAssertFalse(secondResult.didCreate)
        XCTAssertEqual(secondResult.bookmark.id, firstResult.bookmark.id)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.byteOffset, page.startByteOffset)
    }

    func testBookmarkServiceDeletesBookmark() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookmarkRepository(databaseManager: databaseManager)
        let service = ReadingBookmarkService(repository: repository)
        let bookID = UUID()
        let page = ReaderPage(
            bookID: bookID,
            pageIndex: 1,
            byteRange: 256..<512,
            text: "Deletable Bookmark"
        )
        let result = try await service.addBookmark(bookID: bookID, page: page)

        try await service.deleteBookmark(result.bookmark)
        let bookmarks = try await service.bookmarks(bookID: bookID)

        XCTAssertTrue(bookmarks.isEmpty)
    }

    func testBookmarkServiceBuildsStableTitleFromWhitespace() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookmarkRepository(databaseManager: databaseManager)
        let service = ReadingBookmarkService(repository: repository)
        let bookID = UUID()
        let page = ReaderPage(
            bookID: bookID,
            pageIndex: 2,
            byteRange: 4_096..<4_512,
            text: "\n   Chapter   One\t\tThe   Start   \nBody"
        )

        let result = try await service.addBookmark(bookID: bookID, page: page)

        XCTAssertEqual(result.bookmark.title, "Chapter One The Start")
    }

    func testBookmarkServiceFallsBackToStableOffsetTitle() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookmarkRepository(databaseManager: databaseManager)
        let service = ReadingBookmarkService(repository: repository)
        let bookID = UUID()
        let page = ReaderPage(
            bookID: bookID,
            pageIndex: 2,
            byteRange: 4_096..<4_512,
            text: "\n   \t   \n"
        )

        let result = try await service.addBookmark(bookID: bookID, page: page)

        XCTAssertEqual(result.bookmark.title, "\u{4F4D}\u{7F6E} 4096")
    }
}
