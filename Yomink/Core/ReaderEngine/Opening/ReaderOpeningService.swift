import Foundation

enum ReaderOpeningError: Error {
    case bookNotFound
    case emptyVisiblePage
}

final class ReaderOpeningService: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let progressStore: ReadingProgressStore

    init(bookRepository: BookRepository, progressStore: ReadingProgressStore) {
        self.bookRepository = bookRepository
        self.progressStore = progressStore
    }

    func openFirstPage(_ request: ReaderOpeningRequest) async throws -> ReaderOpeningResult {
        try await Task.detached(priority: .userInitiated) { [bookRepository, progressStore] in
            guard let book = try bookRepository.fetchBook(id: request.bookID) else {
                throw ReaderOpeningError.bookNotFound
            }

            let savedProgress = try progressStore.progress(for: request.bookID)
            let startByteOffset = request.preferredByteOffset ?? savedProgress?.byteOffset ?? 0
            let layout = request.layout
            let progress = savedProgress ?? ReadingProgress(
                bookID: request.bookID,
                byteOffset: startByteOffset,
                updatedAt: Date()
            )

            let mapping = try BookFileMapping(fileURL: book.fileURL)
            let clampedStart = min(startByteOffset, mapping.fileSize - 1)
            let upperBound = min(
                mapping.fileSize,
                clampedStart + BookFileMapping.maximumWindowLength
            )
            let windowData = try mapping.bytes(in: clampedStart..<upperBound)
            let decodedText = try TextDecoder().decodeWindow(data: windowData, encoding: book.encoding)
            let textWindow = TextWindow(
                byteRange: clampedStart..<upperBound,
                text: decodedText.prefixUTF16Units(CoreTextPaginator.maximumUTF16Length)
            )
            let pagination = try CoreTextPaginator().paginateFirstPageWithText(
                window: textWindow,
                layout: layout,
                bookID: book.id,
                encoding: book.encoding
            )
            guard !pagination.text.isEmpty else {
                throw ReaderOpeningError.emptyVisiblePage
            }

            let page = ReaderPage(
                bookID: book.id,
                pageIndex: pagination.pageByteRange.pageIndex,
                byteRange: pagination.pageByteRange.byteRange,
                text: pagination.text
            )

            try bookRepository.updateLastReadAt(bookID: book.id)
            return ReaderOpeningResult(book: book, page: page, progress: progress)
        }.value
    }
}

private extension String {
    func prefixUTF16Units(_ length: Int) -> String {
        let clampedLength = max(0, min(length, utf16.count))
        var utf16Index = utf16.index(utf16.startIndex, offsetBy: clampedLength)
        if let endIndex = String.Index(utf16Index, within: self) {
            return String(self[..<endIndex])
        }
        utf16Index = utf16.index(before: utf16Index)
        let endIndex = String.Index(utf16Index, within: self) ?? startIndex
        return String(self[..<endIndex])
    }
}
