import Foundation

enum ReaderOpeningError: Error {
    case bookNotFound
    case emptyVisiblePage
}

final class ReaderOpeningService: @unchecked Sendable {
    // Forward opening only needs enough text to fill one visible page; keeping this below the mmap guard cap
    // avoids decoding a full 1MB window during catalog jumps.
    private static let forwardPageWindowLength: UInt64 = 256 * 1024

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
            let requestedUpperBound = request.upperBoundByteOffset.map {
                min(mapping.fileSize, max(clampedStart + 1, $0))
            } ?? mapping.fileSize
            let upperBound = min(
                requestedUpperBound,
                clampedStart + Self.forwardPageWindowLength
            )
            let windowData = try mapping.bytes(in: clampedStart..<upperBound)
            let decodedWindow = try TextDecoder().decodeBoundedWindow(data: windowData, encoding: book.encoding)
            let windowStart = clampedStart + decodedWindow.trimmedPrefixByteCount
            let windowEnd = upperBound - decodedWindow.trimmedSuffixByteCount
            let textWindow = TextWindow(
                byteRange: windowStart..<windowEnd,
                text: decodedWindow.text.prefixUTF16Units(CoreTextPaginator.maximumUTF16Length)
            )
            let startsAtParagraphBoundary = try Self.startsAtParagraphBoundary(
                mapping: mapping,
                requestedStartByteOffset: clampedStart,
                encoding: book.encoding
            )
            let pagination = try CoreTextPaginator().paginateFirstPageWithText(
                window: textWindow,
                layout: layout,
                bookID: book.id,
                encoding: book.encoding,
                startsAtParagraphBoundary: startsAtParagraphBoundary
            )
            guard !pagination.text.isEmpty else {
                throw ReaderOpeningError.emptyVisiblePage
            }

            let page = ReaderPage(
                bookID: book.id,
                pageIndex: pagination.pageByteRange.pageIndex,
                byteRange: pagination.pageByteRange.byteRange,
                text: pagination.text,
                startsAtParagraphBoundary: pagination.startsAtParagraphBoundary
            )

            try bookRepository.updateLastReadAt(bookID: book.id)
            return ReaderOpeningResult(book: book, page: page, progress: progress)
        }.value
    }

    private static func startsAtParagraphBoundary(
        mapping: BookFileMapping,
        requestedStartByteOffset: UInt64,
        encoding: TextEncoding
    ) throws -> Bool {
        guard requestedStartByteOffset > 0 else {
            return true
        }

        let probeLength = min(UInt64(16), requestedStartByteOffset)
        let probeStart = requestedStartByteOffset - probeLength
        let probeData = try mapping.bytes(in: probeStart..<requestedStartByteOffset)
        let decoder = TextDecoder()
        let probeText = (try? decoder.decodeBoundedWindow(data: probeData, encoding: encoding).text)
            ?? String(data: probeData, encoding: encoding.stringEncoding)
        guard let previousCharacter = probeText?.last else {
            return true
        }
        return previousCharacter.isNewline
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
