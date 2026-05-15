import Foundation
import GRDB

struct BookSearchResult: Hashable, Sendable {
    let bookID: UUID
    let title: String
    let snippet: String
    let byteOffset: UInt64
}

final class SearchIndexService: @unchecked Sendable {
    private static let chunkByteLength: UInt64 = 32 * 1024
    private static let maximumResultCount = 50

    private let databaseManager: DatabaseManager
    private let bookRepository: BookRepository
    private var indexingTasks: [UUID: Task<Void, Never>] = [:]
    private var suspendedBookIDs: Set<UUID> = []
    private let lock = NSLock()

    init(databaseManager: DatabaseManager, bookRepository: BookRepository) {
        self.databaseManager = databaseManager
        self.bookRepository = bookRepository
    }

    convenience init(databaseManager: DatabaseManager) {
        self.init(
            databaseManager: databaseManager,
            bookRepository: BookRepository(databaseManager: databaseManager)
        )
    }

    deinit {
        cancelAllIndexing()
    }

    func scheduleIndexing(bookID: UUID, startingAt byteOffset: UInt64 = 0) {
        guard !isIndexingSuspended(bookID: bookID) else {
            return
        }
        if hasIndexingTask(bookID: bookID) {
            return
        }

        let task: Task<Void, Never> = Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            await self.buildIndex(bookID: bookID, startingAt: byteOffset)
        }
        storeIndexingTask(task, bookID: bookID)
    }

    func cancelIndexing(bookID: UUID) {
        let task = removeIndexingTask(bookID: bookID)
        task?.cancel()
    }

    func cancelAllIndexing() {
        lock.lock()
        let tasks = indexingTasks.values
        indexingTasks.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    func pauseIndexing(bookID: UUID) {
        lock.lock()
        suspendedBookIDs.insert(bookID)
        let task = indexingTasks.removeValue(forKey: bookID)
        lock.unlock()
        task?.cancel()
    }

    func resumeIndexing(bookID: UUID, startingAt byteOffset: UInt64 = 0) {
        lock.lock()
        suspendedBookIDs.remove(bookID)
        lock.unlock()
        scheduleIndexing(bookID: bookID, startingAt: byteOffset)
    }

    func search(bookID: UUID, query: String) async throws -> [BookSearchResult] {
        let normalizedQuery = Self.normalizedQuery(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return try await Task.detached(priority: .userInitiated) { [databaseManager, bookRepository] in
            let book = try bookRepository.fetchBook(id: bookID)
            let encoding = book?.encoding ?? .utf8
            guard let writer = databaseManager.writer else {
                throw BookRepositoryError.databaseUnavailable
            }

            return try writer.read { database in
                let usesFTS = normalizedQuery.count >= 3
                let rows: [Row]
                if usesFTS {
                    do {
                        rows = try Row.fetchAll(
                            database,
                            sql: Self.searchSQL(usesFTS: true),
                            arguments: Self.searchArguments(
                                bookID: bookID,
                                query: normalizedQuery,
                                usesFTS: true
                            )
                        )
                    } catch {
                        rows = try Row.fetchAll(
                            database,
                            sql: Self.searchSQL(usesFTS: false),
                            arguments: Self.searchArguments(
                                bookID: bookID,
                                query: normalizedQuery,
                                usesFTS: false
                            )
                        )
                    }
                } else {
                    rows = try Row.fetchAll(
                        database,
                        sql: Self.searchSQL(usesFTS: false),
                        arguments: Self.searchArguments(
                            bookID: bookID,
                            query: normalizedQuery,
                            usesFTS: false
                        )
                    )
                }
                return rows.compactMap { row in
                    Self.makeSearchResult(row: row, query: normalizedQuery, encoding: encoding)
                }
            }
        }.value
    }

    func indexedUntilByteOffset(bookID: UUID) throws -> UInt64 {
        guard let writer = databaseManager.writer else {
            return 0
        }

        return try writer.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT indexedUntilByteOffset FROM bookSearchIndexStates WHERE bookID = ?",
                arguments: [bookID.uuidString]
            ) else {
                return 0
            }
            let value: Int64 = row["indexedUntilByteOffset"]
            return UInt64(max(Int64(0), value))
        }
    }

    private func buildIndex(bookID: UUID, startingAt requestedByteOffset: UInt64) async {
        defer {
            removeIndexingTask(bookID: bookID)
        }

        do {
            guard let book = try bookRepository.fetchBook(id: bookID) else {
                return
            }

            let mapping = try BookFileMapping(fileURL: book.fileURL)
            let storedOffset = try indexedUntilByteOffset(bookID: bookID)
            var startByteOffset = min(mapping.fileSize, max(storedOffset, requestedByteOffset))
            var chunkIndex = try nextChunkIndex(bookID: bookID)

            while startByteOffset < mapping.fileSize {
                try Task.checkCancellation()

                let upperBound = min(mapping.fileSize, startByteOffset + Self.chunkByteLength)
                let windowData = try mapping.bytes(in: startByteOffset..<upperBound)
                let decodedWindow = try TextDecoder().decodeBoundedWindow(data: windowData, encoding: book.encoding)
                let chunkStartByteOffset = startByteOffset + decodedWindow.trimmedPrefixByteCount
                let chunkEndByteOffset = upperBound - decodedWindow.trimmedSuffixByteCount

                if !decodedWindow.text.isEmpty, chunkStartByteOffset < chunkEndByteOffset {
                    try insertChunk(
                        bookID: bookID,
                        chunkIndex: chunkIndex,
                        startByteOffset: chunkStartByteOffset,
                        endByteOffset: chunkEndByteOffset,
                        content: decodedWindow.text
                    )
                    chunkIndex += 1
                }

                startByteOffset = upperBound
                try updateIndexState(
                    bookID: bookID,
                    indexedUntilByteOffset: startByteOffset,
                    fileSize: mapping.fileSize,
                    completedAt: startByteOffset >= mapping.fileSize ? Date() : nil
                )

                // Full-text indexing is intentionally paced so large books never compete
                // with paging or scrolling for sustained CPU while the reader is open.
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func hasIndexingTask(bookID: UUID) -> Bool {
        lock.lock()
        let hasTask = indexingTasks[bookID] != nil
        lock.unlock()
        return hasTask
    }

    private func isIndexingSuspended(bookID: UUID) -> Bool {
        lock.lock()
        let isSuspended = suspendedBookIDs.contains(bookID)
        lock.unlock()
        return isSuspended
    }

    private func storeIndexingTask(_ task: Task<Void, Never>, bookID: UUID) {
        lock.lock()
        indexingTasks[bookID] = task
        lock.unlock()
    }

    @discardableResult
    private func removeIndexingTask(bookID: UUID) -> Task<Void, Never>? {
        lock.lock()
        let task = indexingTasks.removeValue(forKey: bookID)
        lock.unlock()
        return task
    }

    private func insertChunk(
        bookID: UUID,
        chunkIndex: Int,
        startByteOffset: UInt64,
        endByteOffset: UInt64,
        content: String
    ) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: """
                INSERT INTO bookSearchIndex (bookID, chunkIndex, startByteOffset, endByteOffset, content)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    bookID.uuidString,
                    chunkIndex,
                    Int64(startByteOffset),
                    Int64(endByteOffset),
                    content
                ]
            )
        }
    }

    private func updateIndexState(
        bookID: UUID,
        indexedUntilByteOffset: UInt64,
        fileSize: UInt64,
        completedAt: Date?
    ) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: """
                INSERT INTO bookSearchIndexStates (bookID, indexedUntilByteOffset, fileSize, updatedAt, completedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(bookID) DO UPDATE SET
                    indexedUntilByteOffset = excluded.indexedUntilByteOffset,
                    fileSize = excluded.fileSize,
                    updatedAt = excluded.updatedAt,
                    completedAt = excluded.completedAt
                """,
                arguments: [
                    bookID.uuidString,
                    Int64(indexedUntilByteOffset),
                    Int64(fileSize),
                    Date().timeIntervalSince1970,
                    completedAt?.timeIntervalSince1970
                ]
            )
        }
    }

    private func nextChunkIndex(bookID: UUID) throws -> Int {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        return try writer.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT MAX(chunkIndex) AS maxChunkIndex FROM bookSearchIndex WHERE bookID = ?",
                arguments: [bookID.uuidString]
            ) else {
                return 0
            }

            let value: Int? = row["maxChunkIndex"]
            return (value ?? -1) + 1
        }
    }

    private static func searchSQL(usesFTS: Bool) -> String {
        if usesFTS {
            return """
            SELECT bookID, startByteOffset, endByteOffset, content
            FROM bookSearchIndex
            WHERE bookSearchIndex MATCH ? AND bookID = ?
            ORDER BY startByteOffset ASC
            LIMIT ?
            """
        }

        return """
        SELECT bookID, startByteOffset, endByteOffset, content
        FROM bookSearchIndex
        WHERE bookID = ? AND content COLLATE NOCASE LIKE ? ESCAPE '\'
        ORDER BY startByteOffset ASC
        LIMIT ?
        """
    }

    private static func searchArguments(
        bookID: UUID,
        query: String,
        usesFTS: Bool
    ) -> StatementArguments {
        if usesFTS {
            return [Self.ftsPhrase(for: query), bookID.uuidString, Self.maximumResultCount]
        }
        return [
            bookID.uuidString,
            Self.likePattern(for: query),
            Self.maximumResultCount
        ]
    }

    private static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ftsPhrase(for query: String) -> String {
        let escapedQuery = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedQuery)\""
    }

    private static func likePattern(for query: String) -> String {
        let escapedQuery = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escapedQuery)%"
    }

    private static func makeSearchResult(row: Row, query: String, encoding: TextEncoding) -> BookSearchResult? {
        let bookIDString: String = row["bookID"]
        let startByteOffset: Int64 = row["startByteOffset"]
        let content: String = row["content"]
        guard let bookID = UUID(uuidString: bookIDString) else {
            return nil
        }

        let matchRange = content.range(
            of: query.trimmingCharacters(in: .whitespacesAndNewlines),
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        let snippet = makeSnippet(content: content, matchRange: matchRange)
        let byteOffset = estimateMatchByteOffset(
            chunkStartByteOffset: UInt64(max(Int64(0), startByteOffset)),
            content: content,
            matchRange: matchRange,
            encoding: encoding
        )

        return BookSearchResult(
            bookID: bookID,
            title: snippet.title,
            snippet: snippet.body,
            byteOffset: byteOffset
        )
    }

    private static func makeSnippet(
        content: String,
        matchRange: Range<String.Index>?
    ) -> (title: String, body: String) {
        let line = selectedLine(from: content, matchRange: matchRange)
        let normalizedLine = line.normalizedSearchLine()
        let title = normalizedLine.prefixCharacters(24)
        return (
            title: title.isEmpty ? "\u{641C}\u{7D22}\u{7ED3}\u{679C}" : title,
            body: normalizedLine.prefixCharacters(96)
        )
    }

    private static func selectedLine(from content: String, matchRange: Range<String.Index>?) -> String {
        guard let matchRange else {
            return content
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
                ?? content
        }

        let lowerBound = content[..<matchRange.lowerBound].lastIndex(where: \.isNewline)
            .map { content.index(after: $0) }
            ?? content.startIndex
        let upperBound = content[matchRange.upperBound...].firstIndex(where: \.isNewline)
            ?? content.endIndex
        return String(content[lowerBound..<upperBound])
    }

    private static func estimateMatchByteOffset(
        chunkStartByteOffset: UInt64,
        content: String,
        matchRange: Range<String.Index>?,
        encoding: TextEncoding
    ) -> UInt64 {
        guard let matchRange else {
            return chunkStartByteOffset
        }

        let prefix = content[..<matchRange.lowerBound]
        let byteCount = String(prefix).data(using: encoding.stringEncoding)?.count ?? String(prefix).utf8.count
        return chunkStartByteOffset + UInt64(byteCount)
    }
}

private extension String {
    func normalizedSearchLine() -> String {
        var result = ""
        var shouldAppendSpace = false

        for scalar in unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !result.isEmpty {
                    shouldAppendSpace = true
                }
                continue
            }

            if shouldAppendSpace {
                result.append(" ")
                shouldAppendSpace = false
            }
            result.append(String(scalar))
        }

        return result
    }

    func prefixCharacters(_ count: Int) -> String {
        guard self.count > count else {
            return self
        }
        return String(prefix(count))
    }
}
