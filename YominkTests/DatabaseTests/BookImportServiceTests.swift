import XCTest
@testable import Yomink

final class BookImportServiceTests: XCTestCase {
    func testBookImportServiceCopiesTXTAndStoresMetadata() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookRepository(databaseManager: databaseManager)
        let service = BookImportService(bookRepository: repository)
        let sourceURL = try makeTemporaryTextFile(
            text: "Yomink Import Sample\n" + String(repeating: "content\n", count: 512)
        )

        let book = try await service.importBook(from: sourceURL)
        let storedBook = try repository.fetchBook(id: book.id)

        XCTAssertEqual(storedBook?.id, book.id)
        XCTAssertEqual(storedBook?.title, "Yomink Import Sample")
        XCTAssertEqual(storedBook?.encoding, .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.filePath))
        XCTAssertEqual(BookImportService.sampleLength, 64 * 1024)
    }

    func testBookImportServiceRejectsDuplicateByDefault() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookRepository(databaseManager: databaseManager)
        let service = BookImportService(bookRepository: repository)
        let sourceURL = try makeTemporaryTextFile(
            text: "Same Book\n" + String(repeating: "content\n", count: 512)
        )

        let firstBook = try await service.importBook(from: sourceURL)

        do {
            _ = try await service.importBook(from: sourceURL)
            XCTFail("Expected duplicate import to throw.")
        } catch BookImportError.duplicateBook(let duplicate) {
            XCTAssertEqual(duplicate.existingBook.id, firstBook.id)
            XCTAssertEqual(duplicate.importedTitle, "Same Book")
            XCTAssertEqual(duplicate.copyTitle, "Same Book-\u{526F}\u{672C}")
        }
    }

    func testBookImportServiceCanCreateDuplicateCopy() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let repository = BookRepository(databaseManager: databaseManager)
        let service = BookImportService(bookRepository: repository)
        let sourceURL = try makeTemporaryTextFile(
            text: "Same Book\n" + String(repeating: "content\n", count: 512)
        )

        let firstBook = try await service.importBook(from: sourceURL)
        let copyBook = try await service.importBook(from: sourceURL, duplicateResolution: .createCopy)
        let storedBooks = try repository.fetchBooks()

        XCTAssertNotEqual(copyBook.id, firstBook.id)
        XCTAssertEqual(copyBook.title, "Same Book-\u{526F}\u{672C}")
        XCTAssertEqual(storedBooks.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyBook.filePath))
    }

    private func makeTemporaryTextFile(text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("sample.txt")
        try Data(text.utf8).write(to: fileURL)
        return fileURL
    }
}

