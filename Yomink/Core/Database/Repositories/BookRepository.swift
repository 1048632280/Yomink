import Foundation
import GRDB

enum BookRepositoryError: Error {
    case databaseUnavailable
}

final class BookRepository: @unchecked Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func insertImportedBook(_ book: BookRecord) throws -> BookRecord {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: """
                INSERT INTO books (id, title, author, filePath, encoding, fileSize, importedAt, lastReadAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: book.databaseArguments
            )
        }
        return book
    }

    func fetchBook(id: UUID) throws -> BookRecord? {
        guard let writer = databaseManager.writer else {
            return nil
        }

        return try writer.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT id, title, author, filePath, encoding, fileSize, importedAt, lastReadAt
                FROM books
                WHERE id = ?
                """,
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return BookRecord(databaseRow: row)
        }
    }

    func fetchBooks(sortMode: BookshelfSortMode) throws -> [BookRecord] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            let sql: String
            switch sortMode {
            case .importedAt:
                sql = """
                SELECT id, title, author, filePath, encoding, fileSize, importedAt, lastReadAt
                FROM books
                ORDER BY importedAt DESC
                """
            case .lastReadAt:
                sql = """
                SELECT id, title, author, filePath, encoding, fileSize, importedAt, lastReadAt
                FROM books
                ORDER BY lastReadAt DESC, importedAt DESC
                """
            }

            return try Row.fetchAll(database, sql: sql).map(BookRecord.init(databaseRow:))
        }
    }

    func fetchBooks() throws -> [BookRecord] {
        try fetchBooks(sortMode: .lastReadAt)
    }

    func updateLastReadAt(bookID: UUID) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "UPDATE books SET lastReadAt = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, bookID.uuidString]
            )
        }
    }
}

private extension BookRecord {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            title,
            author,
            filePath,
            encoding.rawValue,
            Int64(fileSize),
            importedAt.timeIntervalSince1970,
            lastReadAt?.timeIntervalSince1970
        ]
    }

    init(databaseRow row: Row) {
        let idString: String = row["id"]
        let encodingRawValue: String = row["encoding"]
        let fileSize: Int64 = row["fileSize"]
        let importedAt: Double = row["importedAt"]
        let lastReadAt: Double? = row["lastReadAt"]

        self.init(
            id: UUID(uuidString: idString) ?? UUID(),
            title: row["title"],
            author: row["author"],
            filePath: row["filePath"],
            encoding: TextEncoding(rawValue: encodingRawValue) ?? .utf8,
            fileSize: UInt64(max(Int64(0), fileSize)),
            importedAt: Date(timeIntervalSince1970: importedAt),
            lastReadAt: lastReadAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
