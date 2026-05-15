import Foundation

struct BookDetailSummary: Hashable, Sendable {
    let book: BookRecord
    let estimatedCharacterCount: UInt64
    let chapters: [ReadingChapter]
}

final class BookDetailService: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let chapterRepository: ChapterRepository

    init(bookRepository: BookRepository, chapterRepository: ChapterRepository) {
        self.bookRepository = bookRepository
        self.chapterRepository = chapterRepository
    }

    func detail(for bookID: UUID) async throws -> BookDetailSummary? {
        try await Task.detached(priority: .utility) { [bookRepository, chapterRepository] in
            guard let book = try bookRepository.fetchBook(id: bookID) else {
                return nil
            }
            let chapters = try chapterRepository.fetchChapters(bookID: bookID)
            return BookDetailSummary(
                book: book,
                estimatedCharacterCount: Self.estimatedCharacterCount(fileSize: book.fileSize, encoding: book.encoding),
                chapters: Array(chapters.prefix(20))
            )
        }.value
    }

    func updateBook(bookID: UUID, title: String, author: String?, summary: String?) async throws -> BookRecord? {
        try await Task.detached(priority: .utility) { [bookRepository] in
            try bookRepository.updateBookDetails(bookID: bookID, title: title, author: author, summary: summary)
        }.value
    }

    private static func estimatedCharacterCount(fileSize: UInt64, encoding: TextEncoding) -> UInt64 {
        switch encoding {
        case .utf16LittleEndian:
            return fileSize / 2
        case .gb18030, .gbk, .gb2312:
            return fileSize / 2
        case .utf8:
            return fileSize
        }
    }
}
