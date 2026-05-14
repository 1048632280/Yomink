import CoreGraphics
import XCTest
@testable import Yomink

final class ReaderOpeningServiceTests: XCTestCase {
    func testBookFileMappingRejectsWindowsLargerThanOneMegabyte() throws {
        let fileURL = try makeTemporaryTextFile(text: String(repeating: "a", count: 1_100_000))
        let mapping = try BookFileMapping(fileURL: fileURL)

        XCTAssertThrowsError(
            try mapping.bytes(in: 0..<(BookFileMapping.maximumWindowLength + 1))
        )
    }

    func testReaderOpeningServiceCreatesFirstPageFromSmallTXT() async throws {
        let databaseManager = try makeTestDatabaseManager()
        let repository = BookRepository(databaseManager: databaseManager)
        let progressStore = ReadingProgressStore(databaseManager: databaseManager)
        let service = ReaderOpeningService(bookRepository: repository, progressStore: progressStore)
        let fileURL = try makeTemporaryTextFile(text: "第一章\nYomink reads with mmap and CoreText.\n")
        let book = BookRecord(
            id: UUID(),
            title: "Sample",
            author: nil,
            filePath: fileURL.path,
            encoding: .utf8,
            fileSize: (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0,
            importedAt: Date(),
            lastReadAt: nil
        )
        _ = try repository.insertImportedBook(book)

        let request = ReaderOpeningRequest(
            bookID: book.id,
            viewportSize: CGSize(width: 320, height: 480),
            layout: .defaultPhone,
            preferredByteOffset: nil
        )
        let result = try await service.openFirstPage(request)

        XCTAssertEqual(result.book.id, book.id)
        XCTAssertFalse(result.page.text.isEmpty)
        XCTAssertEqual(result.page.startByteOffset, 0)
    }

    private func makeTestDatabaseManager() throws -> DatabaseManager {
        try DatabaseManager.inMemory()
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
