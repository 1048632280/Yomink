import XCTest
@testable import Yomink

final class SearchIndexServiceTests: XCTestCase {
    func testSearchIndexServiceIndexesChunksAndFindsSnippet() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let service = SearchIndexService(
            databaseManager: databaseManager,
            bookRepository: bookRepository
        )
        let fileURL = try makeTemporaryTextFile(
            text: """
            第一章 开始
            Yomink builds a local index.
            第二章 搜索
            The rarekeyword appears in this paragraph.
            """
        )
        let book = try insertBook(fileURL: fileURL, repository: bookRepository)

        service.scheduleIndexing(bookID: book.id)
        let results = try await waitForResults(service: service, bookID: book.id, query: "rarekeyword")

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].snippet.contains("rarekeyword"))
        XCTAssertGreaterThan(results[0].byteOffset, 0)
    }

    func testSearchIndexServiceReturnsEmptyForUnindexedBook() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let service = SearchIndexService(
            databaseManager: databaseManager,
            bookRepository: bookRepository
        )

        let results = try await service.search(bookID: UUID(), query: "anything")

        XCTAssertTrue(results.isEmpty)
    }

    func testSearchIndexServiceFindsShortQueriesWithoutFullBookScan() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let service = SearchIndexService(
            databaseManager: databaseManager,
            bookRepository: bookRepository
        )
        let fileURL = try makeTemporaryTextFile(text: "An ox appears in a tiny indexed phrase.")
        let book = try insertBook(fileURL: fileURL, repository: bookRepository)

        service.scheduleIndexing(bookID: book.id)
        let results = try await waitForResults(service: service, bookID: book.id, query: "ox")

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].snippet.contains("ox"))
    }

    func testSearchIndexServiceTreatsFTSSyntaxAsLiteralText() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let service = SearchIndexService(
            databaseManager: databaseManager,
            bookRepository: bookRepository
        )
        let fileURL = try makeTemporaryTextFile(text: "The marker needle+symbol belongs to the story.")
        let book = try insertBook(fileURL: fileURL, repository: bookRepository)

        service.scheduleIndexing(bookID: book.id)
        let results = try await waitForResults(service: service, bookID: book.id, query: "needle+symbol")

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].snippet.contains("needle+symbol"))
    }

    private func waitForResults(
        service: SearchIndexService,
        bookID: UUID,
        query: String
    ) async throws -> [BookSearchResult] {
        for _ in 0..<20 {
            let results = try await service.search(bookID: bookID, query: query)
            if !results.isEmpty {
                return results
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return try await service.search(bookID: bookID, query: query)
    }

    private func insertBook(fileURL: URL, repository: BookRepository) throws -> BookRecord {
        let book = BookRecord(
            id: UUID(),
            title: "Searchable",
            author: nil,
            filePath: fileURL.path,
            encoding: .utf8,
            fileSize: (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0,
            importedAt: Date(),
            lastReadAt: nil
        )
        return try repository.insertImportedBook(book)
    }

    private func makeTemporaryTextFile(text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("search.txt")
        try Data(text.utf8).write(to: fileURL)
        return fileURL
    }
}
