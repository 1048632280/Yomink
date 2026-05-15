import Foundation
import GRDB

final class ChapterRepository: @unchecked Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func deleteChapters(bookID: UUID) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "DELETE FROM chapters WHERE bookID = ?",
                arguments: [bookID.uuidString]
            )
        }
    }

    func clearParsingState(bookID: UUID) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "DELETE FROM chapterParseStates WHERE bookID = ?",
                arguments: [bookID.uuidString]
            )
        }
    }

    func insertChapters(_ chapters: [ReadingChapter]) throws {
        guard !chapters.isEmpty else {
            return
        }
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            for chapter in chapters {
                try database.execute(
                    sql: """
                    INSERT OR IGNORE INTO chapters (id, bookID, title, byteOffset, sortIndex, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: chapter.databaseArguments
                )
            }
        }
    }

    func fetchChapters(bookID: UUID) throws -> [ReadingChapter] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookID, title, byteOffset, sortIndex, createdAt
                FROM chapters
                WHERE bookID = ?
                ORDER BY byteOffset ASC, sortIndex ASC
                """,
                arguments: [bookID.uuidString]
            ).map(ReadingChapter.init(databaseRow:))
        }
    }

    func isParsingCompleted(bookID: UUID) throws -> Bool {
        guard let writer = databaseManager.writer else {
            return false
        }

        return try writer.read { database in
            try Row.fetchOne(
                database,
                sql: "SELECT bookID FROM chapterParseStates WHERE bookID = ?",
                arguments: [bookID.uuidString]
            ) != nil
        }
    }

    func markParsingCompleted(bookID: UUID, completedAt: Date = Date()) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: """
                INSERT INTO chapterParseStates (bookID, completedAt)
                VALUES (?, ?)
                ON CONFLICT(bookID) DO UPDATE SET
                    completedAt = excluded.completedAt
                """,
                arguments: [
                    bookID.uuidString,
                    completedAt.timeIntervalSince1970
                ]
            )
        }
    }
}

private extension ReadingChapter {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            bookID.uuidString,
            title,
            Int64(byteOffset),
            sortIndex,
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
            sortIndex: row["sortIndex"],
            createdAt: Date(timeIntervalSince1970: storedCreatedAt)
        )
    }
}
