import XCTest
@testable import Yomink

final class ReaderFeatureSettingsTests: XCTestCase {
    func testContentFilterRepositoryPersistsAndAppliesWindowRules() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = ContentFilterRepository(databaseManager: databaseManager)
        let service = ContentFilterService(repository: repository)
        let bookID = UUID()

        _ = try await service.addRule(bookID: bookID, sourceText: "badword", replacementText: "")
        _ = try await service.addRule(bookID: bookID, sourceText: "alias", replacementText: "name")

        let rules = try await service.rules(bookID: bookID)
        let filteredText = service.applyRules(rules, to: "badword and alias stay local")

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(filteredText, " and name stay local")
    }

    func testTapAreaSettingsStorePersistsNineAreaActions() throws {
        let databaseManager = try DatabaseManager.inMemory()
        let store = TapAreaSettingsStore(databaseManager: databaseManager)
        let bookID = UUID()
        var settings = TapAreaSettings.standard
        settings.setAction(.toggleMenu, for: 0)
        settings.setAction(.previousPage, for: 4)
        settings.setAction(.nextPage, for: 8)

        try store.save(settings, bookID: bookID)
        let loaded = try store.load(bookID: bookID)

        XCTAssertEqual(loaded.action(for: 0), .toggleMenu)
        XCTAssertEqual(loaded.action(for: 4), .previousPage)
        XCTAssertEqual(loaded.action(for: 8), .nextPage)
    }

    func testBookDetailServiceUpdatesEditableMetadata() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let chapterRepository = ChapterRepository(databaseManager: databaseManager)
        let service = BookDetailService(bookRepository: bookRepository, chapterRepository: chapterRepository)
        let fileURL = try makeTemporaryTextFile(text: "Yomink detail")
        let book = BookRecord(
            id: UUID(),
            title: "Original",
            author: nil,
            filePath: fileURL.path,
            encoding: .utf8,
            fileSize: (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0,
            importedAt: Date(),
            lastReadAt: nil
        )
        _ = try bookRepository.insertImportedBook(book)

        let updatedBook = try await service.updateBook(
            bookID: book.id,
            title: "Updated",
            author: "Author",
            summary: "Summary"
        )
        let detail = try await service.detail(for: book.id)

        XCTAssertEqual(updatedBook?.title, "Updated")
        XCTAssertEqual(detail?.book.author, "Author")
        XCTAssertEqual(detail?.book.summary, "Summary")
    }

    private func makeTemporaryTextFile(text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("feature.txt")
        try Data(text.utf8).write(to: fileURL)
        return fileURL
    }
}
