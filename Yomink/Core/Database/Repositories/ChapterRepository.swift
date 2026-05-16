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

    func resetParsingData(bookID: UUID) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "DELETE FROM chapters WHERE bookID = ?",
                arguments: [bookID.uuidString]
            )
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

    @discardableResult
    func insertChapters(_ chapters: [ReadingChapter], state: ChapterParseState) throws -> Int {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        return try writer.write { database in
            for chapter in chapters {
                try database.execute(
                    sql: """
                    INSERT OR IGNORE INTO chapters (id, bookID, title, byteOffset, sortIndex, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: chapter.databaseArguments
                )
            }
            let actualNextSortIndex = try Self.nextSortIndex(bookID: state.bookID, database: database)
            let normalizedState = state.withNextSortIndex(actualNextSortIndex)
            try Self.upsertParsingState(normalizedState, database: database)
            return actualNextSortIndex
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

    func fetchParsingState(bookID: UUID) throws -> ChapterParseState? {
        guard let writer = databaseManager.writer else {
            return nil
        }

        return try writer.read { database in
            try Self.fetchParsingState(bookID: bookID, database: database)
        }
    }

    func fetchCatalogSnapshot(bookID: UUID) throws -> ChapterCatalogSnapshot {
        guard let writer = databaseManager.writer else {
            return ChapterCatalogSnapshot(chapters: [], state: nil)
        }

        return try writer.read { database in
            let chapters = try Self.fetchChapters(bookID: bookID, database: database)
            let state = try Self.fetchParsingState(bookID: bookID, database: database)
            return ChapterCatalogSnapshot(chapters: chapters, state: state)
        }
    }

    func isParsingCompleted(bookID: UUID) throws -> Bool {
        guard let writer = databaseManager.writer else {
            return false
        }

        return try writer.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT completedAt FROM chapterParseStates WHERE bookID = ?",
                arguments: [bookID.uuidString]
            ) else {
                return false
            }
            let completedAt: Double = row["completedAt"]
            return completedAt > 0
        }
    }

    func markParsingCompleted(bookID: UUID, completedAt: Date = Date()) throws {
        let nextSortIndex = try nextSortIndex(bookID: bookID)
        try updateParsingState(
            bookID: bookID,
            scannedUntilByteOffset: 0,
            fileSize: 0,
            nextSortIndex: nextSortIndex,
            completedAt: completedAt,
            failureReason: nil
        )
    }

    func updateParsingState(
        bookID: UUID,
        scannedUntilByteOffset: UInt64,
        fileSize: UInt64,
        nextSortIndex: Int,
        completedAt: Date?,
        failureReason: String? = nil,
        updatedAt: Date = Date()
    ) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        let state = ChapterParseState(
            bookID: bookID,
            scannedUntilByteOffset: scannedUntilByteOffset,
            fileSize: fileSize,
            nextSortIndex: nextSortIndex,
            updatedAt: updatedAt,
            completedAt: completedAt,
            failureReason: failureReason
        )

        try writer.write { database in
            try Self.upsertParsingState(state, database: database)
        }
    }

    func nextSortIndex(bookID: UUID) throws -> Int {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        return try writer.read { database in
            try Self.nextSortIndex(bookID: bookID, database: database)
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

private extension ChapterRepository {
    static func fetchChapters(bookID: UUID, database: Database) throws -> [ReadingChapter] {
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

    static func fetchParsingState(bookID: UUID, database: Database) throws -> ChapterParseState? {
        try Row.fetchOne(
            database,
            sql: """
            SELECT bookID, scannedUntilByteOffset, fileSize, nextSortIndex, updatedAt, completedAt, failureReason
            FROM chapterParseStates
            WHERE bookID = ?
            """,
            arguments: [bookID.uuidString]
        ).map(ChapterParseState.init(databaseRow:))
    }

    static func upsertParsingState(_ state: ChapterParseState, database: Database) throws {
        try database.execute(
            sql: """
            INSERT INTO chapterParseStates (
                bookID, completedAt, scannedUntilByteOffset, fileSize, nextSortIndex, updatedAt, failureReason
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(bookID) DO UPDATE SET
                completedAt = excluded.completedAt,
                scannedUntilByteOffset = excluded.scannedUntilByteOffset,
                fileSize = excluded.fileSize,
                nextSortIndex = excluded.nextSortIndex,
                updatedAt = excluded.updatedAt,
                failureReason = excluded.failureReason
            """,
            arguments: state.databaseArguments
        )
    }

    static func nextSortIndex(bookID: UUID, database: Database) throws -> Int {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT MAX(sortIndex) AS maxSortIndex FROM chapters WHERE bookID = ?",
            arguments: [bookID.uuidString]
        ) else {
            return 0
        }
        let maxSortIndex: Int? = row["maxSortIndex"]
        return maxSortIndex.map { $0 + 1 } ?? 0
    }
}

private extension ChapterParseState {
    var databaseArguments: StatementArguments {
        [
            bookID.uuidString,
            completedAt?.timeIntervalSince1970 ?? 0,
            Int64(scannedUntilByteOffset),
            Int64(fileSize),
            nextSortIndex,
            updatedAt.timeIntervalSince1970,
            failureReason
        ]
    }

    init(databaseRow row: Row) {
        let bookIDString: String = row["bookID"]
        let scannedUntilByteOffset: Int64 = row["scannedUntilByteOffset"]
        let fileSize: Int64 = row["fileSize"]
        let updatedAt: Double = row["updatedAt"]
        let completedAtValue: Double = row["completedAt"]
        let failureReason: String? = row["failureReason"]

        self.init(
            bookID: UUID(uuidString: bookIDString) ?? UUID(),
            scannedUntilByteOffset: UInt64(max(Int64(0), scannedUntilByteOffset)),
            fileSize: UInt64(max(Int64(0), fileSize)),
            nextSortIndex: row["nextSortIndex"],
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            completedAt: completedAtValue > 0 ? Date(timeIntervalSince1970: completedAtValue) : nil,
            failureReason: failureReason
        )
    }

    func withNextSortIndex(_ nextSortIndex: Int) -> ChapterParseState {
        ChapterParseState(
            bookID: bookID,
            scannedUntilByteOffset: scannedUntilByteOffset,
            fileSize: fileSize,
            nextSortIndex: nextSortIndex,
            updatedAt: updatedAt,
            completedAt: completedAt,
            failureReason: failureReason
        )
    }
}
