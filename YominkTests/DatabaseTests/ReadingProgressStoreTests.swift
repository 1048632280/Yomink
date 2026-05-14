import XCTest
@testable import Yomink

final class ReadingProgressStoreTests: XCTestCase {
    func testReadingProgressStoreSavesAndRestoresByteOffset() throws {
        let databaseManager = try makeTestDatabaseManager()
        let store = ReadingProgressStore(databaseManager: databaseManager)
        let bookID = UUID()

        store.remember(
            ReadingProgress(
                bookID: bookID,
                byteOffset: 4_096,
                updatedAt: Date()
            )
        )
        store.flushPendingProgress()

        let progress = try store.progress(for: bookID)
        XCTAssertEqual(progress?.byteOffset, 4_096)
    }

    private func makeTestDatabaseManager() throws -> DatabaseManager {
        try DatabaseManager.inMemory()
    }
}
