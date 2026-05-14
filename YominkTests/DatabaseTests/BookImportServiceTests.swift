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

    private func makeTemporaryTextFile(text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("sample.txt")
        try Data(text.utf8).write(to: fileURL)
        return fileURL
    }
}

