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

        let bookmark = try await service.addBookmark(bookID: bookID, page: page)
        let bookmarks = try await service.bookmarks(bookID: bookID)

        XCTAssertEqual(bookmark.byteOffset, page.startByteOffset)
        XCTAssertEqual(bookmark.title, "Chapter One")
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.id, bookmark.id)
        XCTAssertEqual(bookmarks.first?.byteOffset, page.startByteOffset)
    }
}
