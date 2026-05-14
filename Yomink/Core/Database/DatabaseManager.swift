import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    let writer: (any DatabaseWriter)?

    init(writer: (any DatabaseWriter)?) {
        self.writer = writer
    }

    static func defaultDatabase() -> DatabaseManager {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yomink", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("Yomink.sqlite")

        do {
            let queue = try DatabaseQueue(path: databaseURL.path)
            try DatabaseMigrator.yominkMigrator.migrate(queue)
            return DatabaseManager(writer: queue)
        } catch {
            assertionFailure("Database initialization failed: \(error)")
            return DatabaseManager(writer: nil)
        }
    }

    static func inMemory() throws -> DatabaseManager {
        let queue = try DatabaseQueue(path: ":memory:")
        try DatabaseMigrator.yominkMigrator.migrate(queue)
        return DatabaseManager(writer: queue)
    }

    func writeProgress(_ progress: ReadingProgress) {
        guard let writer else {
            return
        }

        do {
            try writer.write { database in
                try database.execute(
                    sql: """
                    INSERT INTO readingProgress (bookID, byteOffset, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(bookID) DO UPDATE SET
                        byteOffset = excluded.byteOffset,
                        updatedAt = excluded.updatedAt
                    """,
                    arguments: [
                        progress.bookID.uuidString,
                        Int64(progress.byteOffset),
                        progress.updatedAt.timeIntervalSince1970
                    ]
                )
            }
        } catch {
            assertionFailure("Failed to persist reading progress: \(error)")
        }
    }

    func readProgress(bookID: UUID) throws -> ReadingProgress? {
        guard let writer else {
            return nil
        }

        return try writer.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT bookID, byteOffset, updatedAt FROM readingProgress WHERE bookID = ?",
                arguments: [bookID.uuidString]
            ) else {
                return nil
            }

            let storedBookIDString: String = row["bookID"]
            let storedByteOffset: Int64 = row["byteOffset"]
            let storedUpdatedAt: Double = row["updatedAt"]
            let storedBookID = UUID(uuidString: storedBookIDString) ?? bookID
            let byteOffset = UInt64(max(Int64(0), storedByteOffset))
            let updatedAt = Date(timeIntervalSince1970: storedUpdatedAt)
            return ReadingProgress(
                bookID: storedBookID,
                byteOffset: byteOffset,
                updatedAt: updatedAt
            )
        }
    }
}
