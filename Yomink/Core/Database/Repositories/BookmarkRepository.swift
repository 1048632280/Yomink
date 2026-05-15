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

    func insertIfNeeded(_ bookmark: ReadingBookmark) throws -> ReadingBookmarkAddResult {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        return try writer.write { database in
            if let existingBookmark = try fetchBookmark(
                bookID: bookmark.bookID,
                byteOffset: bookmark.byteOffset,
                database: database
            ) {
                return ReadingBookmarkAddResult(bookmark: existingBookmark, didCreate: false)
            }

            try database.execute(
                sql: """
                INSERT INTO bookmarks (id, bookID, title, byteOffset, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: bookmark.databaseArguments
            )
            return ReadingBookmarkAddResult(bookmark: bookmark, didCreate: true)
        }
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

    func deleteBookmark(id: UUID, bookID: UUID) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "DELETE FROM bookmarks WHERE id = ? AND bookID = ?",
                arguments: [id.uuidString, bookID.uuidString]
            )
        }
    }

    func fetchBookmark(bookID: UUID, byteOffset: UInt64) throws -> ReadingBookmark? {
        guard let writer = databaseManager.writer else {
            return nil
        }

        return try writer.read { database in
            try fetchBookmark(bookID: bookID, byteOffset: byteOffset, database: database)
        }
    }

    private func fetchBookmark(bookID: UUID, byteOffset: UInt64, database: Database) throws -> ReadingBookmark? {
        try Row.fetchOne(
            database,
            sql: """
            SELECT id, bookID, title, byteOffset, createdAt
            FROM bookmarks
            WHERE bookID = ? AND byteOffset = ?
            LIMIT 1
            """,
            arguments: [bookID.uuidString, Int64(byteOffset)]
        ).map(ReadingBookmark.init(databaseRow:))
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
