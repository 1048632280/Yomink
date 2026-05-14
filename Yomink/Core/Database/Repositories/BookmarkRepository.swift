import Foundation
import GRDB

final class BookmarkRepository: @unchecked Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func insert(_ bookmark: ReadingBookmark) throws -> ReadingBookmark {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: """
                INSERT INTO bookmarks (id, bookID, title, byteOffset, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: bookmark.databaseArguments
            )
        }
        return bookmark
    }

    func fetchBookmarks(bookID: UUID) throws -> [ReadingBookmark] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookID, title, byteOffset, createdAt
                FROM bookmarks
                WHERE bookID = ?
                ORDER BY byteOffset ASC, createdAt ASC
                """,
                arguments: [bookID.uuidString]
            ).map(ReadingBookmark.init(databaseRow:))
        }
    }
}

private extension ReadingBookmark {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            bookID.uuidString,
            title,
            Int64(byteOffset),
            createdAt.timeIntervalSince1970
        ]
    }

    init(databaseRow row: Row) {
        let idString: String = row["id"]
        let bookIDString: String = row["bookID"]
        let storedByteOffset: Int64 = row["byteOffset"]
        let storedCreatedAt: Double = row["createdAt"]

        self.init(
            id: UUID(uuidString: idString) ?? UUID(),
            bookID: UUID(uuidString: bookIDString) ?? UUID(),
            title: row["title"],
            byteOffset: UInt64(max(Int64(0), storedByteOffset)),
            createdAt: Date(timeIntervalSince1970: storedCreatedAt)
        )
    }
}
