import Foundation

final class SearchIndexService {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func scheduleIndexing(bookID: UUID, startingAt byteOffset: UInt64) {
        // Future work: build FTS5 rows from bounded text windows so opening a book never waits on indexing.
        _ = (databaseManager, bookID, byteOffset)
    }
}

