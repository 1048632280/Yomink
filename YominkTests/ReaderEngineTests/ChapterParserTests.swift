import XCTest
@testable import Yomink

final class ChapterParserTests: XCTestCase {
    func testParserFindsChapterHeadingsInsideBoundedWindow() throws {
        let text = [
            "\u{6B63}\u{6587}\u{5F00}\u{59CB}",
            "\u{7B2C}\u{4E00}\u{7AE0} \u{5F00}\u{59CB}",
            "\u{8FD9}\u{4E00}\u{884C}\u{53EA}\u{662F}\u{5185}\u{5BB9}",
            "Chapter 2 Return",
            "\u{5377}\u{4E09} \u{98CE}\u{8D77}"
        ].joined(separator: "\n")
        let data = Data(text.utf8)
        let byteRangeStart: UInt64 = 4_096

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: byteRangeStart..<(byteRangeStart + UInt64(data.count)),
            encoding: .utf8
        )

        XCTAssertEqual(
            candidates.map(\.title),
            [
                "\u{7B2C}\u{4E00}\u{7AE0} \u{5F00}\u{59CB}",
                "Chapter 2 Return",
                "\u{5377}\u{4E09} \u{98CE}\u{8D77}"
            ]
        )
        XCTAssertEqual(
            candidates.first?.byteOffset,
            byteRangeStart + UInt64("\u{6B63}\u{6587}\u{5F00}\u{59CB}\n".utf8.count)
        )
    }

    func testParserSkipsPartialFirstLineInContinuationWindow() throws {
        let text = [
            "\u{7B2C}\u{4E00}\u{7AE0} \u{5E94}\u{8BE5}\u{7531}\u{4E0A}\u{4E00}\u{7A97}\u{53E3}\u{8BC6}\u{522B}",
            "\u{7B2C}\u{4E8C}\u{7AE0} \u{65B0}\u{7A97}\u{53E3}"
        ].joined(separator: "\n")
        let data = Data(text.utf8)

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: 512..<(512 + UInt64(data.count)),
            encoding: .utf8
        )

        XCTAssertEqual(candidates.map(\.title), ["\u{7B2C}\u{4E8C}\u{7AE0} \u{65B0}\u{7A97}\u{53E3}"])
    }

    func testParserDecodesGBKCandidateLines() throws {
        let text = [
            "\u{666E}\u{901A}\u{5185}\u{5BB9}",
            "\u{7B2C}\u{4E09}\u{7AE0} \u{98CE}\u{8D77}"
        ].joined(separator: "\n")
        let data = try XCTUnwrap(text.data(using: TextEncoding.gbk.stringEncoding))

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: 0..<UInt64(data.count),
            encoding: .gbk
        )

        XCTAssertEqual(candidates.map(\.title), ["\u{7B2C}\u{4E09}\u{7AE0} \u{98CE}\u{8D77}"])
    }

    func testParserDecodesUTF16LittleEndianCandidateLines() throws {
        let text = [
            "\u{666E}\u{901A}\u{5185}\u{5BB9}",
            "\u{7B2C}\u{4E94}\u{7AE0} \u{65B0}\u{751F}"
        ].joined(separator: "\n")
        let data = try XCTUnwrap(text.data(using: TextEncoding.utf16LittleEndian.stringEncoding))

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: 0..<UInt64(data.count),
            encoding: .utf16LittleEndian
        )

        XCTAssertEqual(candidates.map(\.title), ["\u{7B2C}\u{4E94}\u{7AE0} \u{65B0}\u{751F}"])
    }

    func testParserSkipsLongLinesWithoutMissingShortChapterTitles() throws {
        let longLine = String(repeating: "\u{8FD9}", count: 400)
        let text = [
            longLine,
            "\u{7B2C}\u{56DB}\u{7AE0} \u{5F52}\u{6765}"
        ].joined(separator: "\n")
        let data = Data(text.utf8)

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: 0..<UInt64(data.count),
            encoding: .utf8
        )

        XCTAssertEqual(candidates.map(\.title), ["\u{7B2C}\u{56DB}\u{7AE0} \u{5F52}\u{6765}"])
    }
}

final class ReadingChapterServiceTests: XCTestCase {
    func testChapterServiceKeepsParsedChaptersAfterCancel() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let chapterRepository = ChapterRepository(databaseManager: databaseManager)
        let service = ReadingChapterService(
            bookRepository: bookRepository,
            chapterRepository: chapterRepository,
            parser: ChapterParser()
        )
        let longParagraph = String(repeating: "\u{6B63}\u{6587}", count: 180)
        let book = try makeImportedBook(
            repository: bookRepository,
            text: [
                "\u{7B2C}\u{4E00}\u{7AE0} \u{5F00}\u{59CB}",
                String(repeating: "\(longParagraph)\n", count: 2_000),
                "\u{7B2C}\u{4E8C}\u{7AE0} \u{7EE7}\u{7EED}"
            ].joined(separator: "\n")
        )
        defer {
            try? FileManager.default.removeItem(at: book.fileURL)
        }

        service.scheduleParsing(bookID: book.id)
        let firstSnapshot = try await waitForSnapshot(service: service, bookID: book.id) {
            !$0.chapters.isEmpty
        }
        service.cancelParsing(bookID: book.id)
        try await Task.sleep(nanoseconds: 20_000_000)

        let snapshotAfterCancel = try await service.catalogSnapshot(
            bookID: book.id,
            scheduleIfNeeded: false
        )

        XCTAssertFalse(firstSnapshot.chapters.isEmpty)
        XCTAssertFalse(snapshotAfterCancel.chapters.isEmpty)
    }

    func testChapterServiceCompletesBookWithoutChapters() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let chapterRepository = ChapterRepository(databaseManager: databaseManager)
        let service = ReadingChapterService(
            bookRepository: bookRepository,
            chapterRepository: chapterRepository,
            parser: ChapterParser()
        )
        let book = try makeImportedBook(
            repository: bookRepository,
            text: String(repeating: "\u{8FD9}\u{662F}\u{666E}\u{901A}\u{6BB5}\u{843D}\n", count: 2_000)
        )
        defer {
            try? FileManager.default.removeItem(at: book.fileURL)
        }

        service.scheduleParsing(bookID: book.id)
        let snapshot = try await waitForSnapshot(service: service, bookID: book.id) {
            $0.status == .completed
        }

        XCTAssertTrue(snapshot.chapters.isEmpty)
        XCTAssertEqual(snapshot.status, .completed)
    }

    func testChapterServiceCompletesEmptyBook() async throws {
        let databaseManager = try DatabaseManager.inMemory()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let chapterRepository = ChapterRepository(databaseManager: databaseManager)
        let service = ReadingChapterService(
            bookRepository: bookRepository,
            chapterRepository: chapterRepository,
            parser: ChapterParser()
        )
        let book = try makeImportedBook(repository: bookRepository, text: "")
        defer {
            try? FileManager.default.removeItem(at: book.fileURL)
        }

        service.scheduleParsing(bookID: book.id)
        let snapshot = try await waitForSnapshot(service: service, bookID: book.id) {
            $0.status == .completed
        }

        XCTAssertTrue(snapshot.chapters.isEmpty)
        XCTAssertEqual(snapshot.status, .completed)
    }

    private func makeImportedBook(repository: BookRepository, text: String) throws -> BookRecord {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        let data = Data(text.utf8)
        try data.write(to: fileURL)
        let book = BookRecord(
            id: UUID(),
            title: "Test",
            author: nil,
            summary: nil,
            groupID: nil,
            filePath: fileURL.path,
            encoding: .utf8,
            fileSize: UInt64(data.count),
            importedAt: Date(),
            lastReadAt: nil
        )
        return try repository.insertImportedBook(book)
    }

    private func waitForSnapshot(
        service: ReadingChapterService,
        bookID: UUID,
        predicate: (ChapterCatalogSnapshot) -> Bool
    ) async throws -> ChapterCatalogSnapshot {
        var latestSnapshot = try await service.catalogSnapshot(bookID: bookID, scheduleIfNeeded: false)
        for _ in 0..<200 {
            latestSnapshot = try await service.catalogSnapshot(bookID: bookID, scheduleIfNeeded: false)
            if predicate(latestSnapshot) {
                return latestSnapshot
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for chapter service snapshot")
        return latestSnapshot
    }
}
