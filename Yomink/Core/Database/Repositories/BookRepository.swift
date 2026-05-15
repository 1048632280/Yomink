import Foundation
import GRDB

enum BookRepositoryError: Error {
    case databaseUnavailable
}

enum BookshelfGroupFilter: Hashable, Sendable {
    case all
    case ungrouped
    case group(UUID)
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
                INSERT INTO books (id, title, author, summary, groupID, filePath, encoding, fileSize, importedAt, lastReadAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                SELECT id, title, author, summary, groupID, filePath, encoding, fileSize, importedAt, lastReadAt
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
            let sql = """
            SELECT id, title, author, summary, groupID, filePath, encoding, fileSize, importedAt, lastReadAt
            FROM books
            \(Self.orderClause(sortMode: sortMode))
            """
            return try Row.fetchAll(database, sql: sql).map(BookRecord.init(databaseRow:))
        }
    }

    func fetchBooks() throws -> [BookRecord] {
        try fetchBooks(sortMode: .lastReadAt)
    }

    func fetchBooks(fileSize: UInt64) throws -> [BookRecord] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT id, title, author, summary, groupID, filePath, encoding, fileSize, importedAt, lastReadAt
                FROM books
                WHERE fileSize = ?
                ORDER BY importedAt ASC
                """,
                arguments: [Int64(fileSize)]
            ).map(BookRecord.init(databaseRow:))
        }
    }

    func fetchBookshelfItems(
        sortMode: BookshelfSortMode,
        groupFilter: BookshelfGroupFilter = .all,
        searchText: String = ""
    ) throws -> [BookshelfBookItem] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            var conditions: [String] = []
            var arguments = StatementArguments()

            switch groupFilter {
            case .all:
                break
            case .ungrouped:
                conditions.append("books.groupID IS NULL")
            case .group(let groupID):
                conditions.append("books.groupID = ?")
                arguments += [groupID.uuidString]
            }

            let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSearchText.isEmpty {
                conditions.append("books.title LIKE ? COLLATE NOCASE")
                arguments += ["%\(trimmedSearchText)%"]
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
            let sql = """
            SELECT books.id, books.title, books.author, books.summary, books.groupID, books.filePath,
                books.encoding, books.fileSize, books.importedAt, books.lastReadAt,
                readingProgress.byteOffset AS progressByteOffset
            FROM books
            LEFT JOIN readingProgress ON readingProgress.bookID = books.id
            \(whereClause)
            \(Self.orderClause(sortMode: sortMode))
            """

            return try Row.fetchAll(database, sql: sql, arguments: arguments)
                .map(BookshelfBookItem.init(databaseRow:))
        }
    }

    func fetchRecentBooks(limit: Int = 20) throws -> [BookshelfBookItem] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT books.id, books.title, books.author, books.summary, books.groupID, books.filePath,
                    books.encoding, books.fileSize, books.importedAt, books.lastReadAt,
                    readingProgress.byteOffset AS progressByteOffset
                FROM books
                LEFT JOIN readingProgress ON readingProgress.bookID = books.id
                WHERE books.lastReadAt IS NOT NULL
                ORDER BY books.lastReadAt DESC, books.importedAt DESC
                LIMIT ?
                """,
                arguments: [max(0, limit)]
            ).map(BookshelfBookItem.init(databaseRow:))
        }
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

    func updateBookDetails(bookID: UUID, title: String, author: String?, summary: String?) throws -> BookRecord? {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            return try fetchBook(id: bookID)
        }

        return try writer.write { database in
            try database.execute(
                sql: """
                UPDATE books
                SET title = ?, author = ?, summary = ?
                WHERE id = ?
                """,
                arguments: [
                    normalizedTitle,
                    author?.trimmedNilIfEmpty,
                    summary?.trimmedNilIfEmpty,
                    bookID.uuidString
                ]
            )
            return try fetchBook(id: bookID, database: database)
        }
    }

    func moveBooks(_ bookIDs: [UUID], toGroupID groupID: UUID?) throws {
        guard !bookIDs.isEmpty else {
            return
        }
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            for bookID in bookIDs {
                try database.execute(
                    sql: "UPDATE books SET groupID = ? WHERE id = ?",
                    arguments: [groupID?.uuidString, bookID.uuidString]
                )
            }
        }
    }

    func deleteBooks(_ bookIDs: [UUID]) throws -> [BookRecord] {
        guard !bookIDs.isEmpty else {
            return []
        }
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        return try writer.write { database in
            var deletedBooks: [BookRecord] = []
            for bookID in bookIDs {
                guard let book = try fetchBook(id: bookID, database: database) else {
                    continue
                }

                deletedBooks.append(book)
                try Self.deleteBookSideData(bookID: bookID, database: database)
                try database.execute(
                    sql: "DELETE FROM books WHERE id = ?",
                    arguments: [bookID.uuidString]
                )
            }
            return deletedBooks
        }
    }

    private func fetchBook(id: UUID, database: Database) throws -> BookRecord? {
        try Row.fetchOne(
            database,
            sql: """
            SELECT id, title, author, summary, groupID, filePath, encoding, fileSize, importedAt, lastReadAt
            FROM books
            WHERE id = ?
            """,
            arguments: [id.uuidString]
        ).map(BookRecord.init(databaseRow:))
    }

    private static func deleteBookSideData(bookID: UUID, database: Database) throws {
        // Book deletion must remove every derived local artifact so no stale progress,
        // catalog, bookmark, or FTS state can point at a missing mmap-backed file.
        let arguments: StatementArguments = [bookID.uuidString]
        try database.execute(sql: "DELETE FROM readingProgress WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM bookmarks WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM chapters WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM chapterParseStates WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM bookSearchIndex WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM bookSearchIndexStates WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM contentFilterRules WHERE bookID = ?", arguments: arguments)
        try database.execute(sql: "DELETE FROM tapAreaSettings WHERE scopeID = ?", arguments: arguments)
    }

    private static func orderClause(sortMode: BookshelfSortMode) -> String {
        switch sortMode {
        case .importedAt:
            return "ORDER BY books.importedAt DESC"
        case .lastReadAt:
            return "ORDER BY books.lastReadAt DESC, books.importedAt DESC"
        }
    }
}

private extension BookRecord {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            title,
            author,
            summary,
            groupID?.uuidString,
            filePath,
            encoding.rawValue,
            Int64(fileSize),
            importedAt.timeIntervalSince1970,
            lastReadAt?.timeIntervalSince1970
        ]
    }

    init(databaseRow row: Row) {
        let idString: String = row["id"]
        let groupIDString: String? = row["groupID"]
        let encodingRawValue: String = row["encoding"]
        let fileSize: Int64 = row["fileSize"]
        let importedAt: Double = row["importedAt"]
        let lastReadAt: Double? = row["lastReadAt"]

        self.init(
            id: UUID(uuidString: idString) ?? UUID(),
            title: row["title"],
            author: row["author"],
            summary: row["summary"],
            groupID: groupIDString.flatMap(UUID.init(uuidString:)),
            filePath: row["filePath"],
            encoding: TextEncoding(rawValue: encodingRawValue) ?? .utf8,
            fileSize: UInt64(max(Int64(0), fileSize)),
            importedAt: Date(timeIntervalSince1970: importedAt),
            lastReadAt: lastReadAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

private extension BookshelfBookItem {
    init(databaseRow row: Row) {
        let book = BookRecord(databaseRow: row)
        let storedByteOffset: Int64? = row["progressByteOffset"]
        let progressByteOffset = UInt64(max(Int64(0), storedByteOffset ?? 0))
        let progress = book.fileSize == 0
            ? 0
            : min(1, Double(progressByteOffset) / Double(book.fileSize))

        self.init(book: book, readingProgress: progress)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
