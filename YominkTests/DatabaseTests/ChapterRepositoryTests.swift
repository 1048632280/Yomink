import XCTest
@testable import Yomink

final class ChapterRepositoryTests: XCTestCase {
    func testChapterRepositoryStoresChaptersByByteOffset() throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = ChapterRepository(databaseManager: databaseManager)
        let bookID = UUID()
        let laterChapter = ReadingChapter(
            bookID: bookID,
            title: "Later",
            byteOffset: 512,
            sortIndex: 1,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let earlierChapter = ReadingChapter(
            bookID: bookID,
            title: "Earlier",
            byteOffset: 128,
            sortIndex: 0,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        try repository.insertChapters([laterChapter, earlierChapter])

        let chapters = try repository.fetchChapters(bookID: bookID)

        XCTAssertEqual(chapters.map(\.title), ["Earlier", "Later"])
        XCTAssertEqual(chapters.map(\.byteOffset), [128, 512])
    }

    func testChapterRepositoryDeletesOnlyOneBookCatalog() throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = ChapterRepository(databaseManager: databaseManager)
        let firstBookID = UUID()
        let secondBookID = UUID()

        try repository.insertChapters([
            ReadingChapter(bookID: firstBookID, title: "First", byteOffset: 0, sortIndex: 0),
            ReadingChapter(bookID: secondBookID, title: "Second", byteOffset: 0, sortIndex: 0)
        ])
        try repository.deleteChapters(bookID: firstBookID)

        XCTAssertTrue(try repository.fetchChapters(bookID: firstBookID).isEmpty)
        XCTAssertEqual(try repository.fetchChapters(bookID: secondBookID).map(\.title), ["Second"])
    }

    func testChapterRepositoryTracksCompletedParsingState() throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = ChapterRepository(databaseManager: databaseManager)
        let bookID = UUID()

        XCTAssertFalse(try repository.isParsingCompleted(bookID: bookID))

        try repository.markParsingCompleted(bookID: bookID, completedAt: Date(timeIntervalSince1970: 1))

        XCTAssertTrue(try repository.isParsingCompleted(bookID: bookID))

        try repository.clearParsingState(bookID: bookID)

        XCTAssertFalse(try repository.isParsingCompleted(bookID: bookID))
    }
}
