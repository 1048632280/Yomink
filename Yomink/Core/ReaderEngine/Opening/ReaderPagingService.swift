import Foundation

enum ReaderPagingError: Error {
    case bookNotFound
    case emptyVisiblePage
    case stalledPageBoundary
}

final class ReaderPagingService: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let pageCache: ReaderPageCache

    init(bookRepository: BookRepository, pageCache: ReaderPageCache) {
        self.bookRepository = bookRepository
        self.pageCache = pageCache
    }

    func removeCachedPages() {
        pageCache.removeAll()
    }

    func page(_ request: ReaderPageRequest) async throws -> ReaderPage? {
        let key = cacheKey(for: request)
        if let cachedPage = pageCache.readerPage(for: key) {
            return cachedPage
        }

        return try await Task.detached(priority: .userInitiated) { [bookRepository, pageCache] in
            guard let book = try bookRepository.fetchBook(id: request.bookID) else {
                throw ReaderPagingError.bookNotFound
            }
            guard request.startByteOffset < book.fileSize else {
                return nil
            }

            let mapping = try BookFileMapping(fileURL: book.fileURL)
            let clampedStart = min(request.startByteOffset, mapping.fileSize - 1)
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
            let pagination = try CoreTextPaginator().paginatePageWithText(
                window: textWindow,
                layout: request.layout,
                bookID: book.id,
                pageIndex: request.pageIndex,
                encoding: book.encoding
            )

            guard !pagination.text.isEmpty else {
                throw ReaderPagingError.emptyVisiblePage
            }
            guard pagination.pageByteRange.endByteOffset > pagination.pageByteRange.startByteOffset else {
                throw ReaderPagingError.stalledPageBoundary
            }

            let page = ReaderPage(
                bookID: book.id,
                pageIndex: request.pageIndex,
                byteRange: pagination.pageByteRange.byteRange,
                text: pagination.text
            )
            pageCache.insert(page, for: key)
            return page
        }.value
    }

    private func cacheKey(for request: ReaderPageRequest) -> String {
        [
            request.bookID.uuidString,
            "\(request.startByteOffset)",
            "\(request.pageIndex)",
            "\(Int(request.layout.viewportSize.width))x\(Int(request.layout.viewportSize.height))",
            request.layout.fontName,
            "\(request.layout.fontSize)",
            "\(request.layout.lineSpacing)",
            "\(request.layout.paragraphSpacing)"
        ].joined(separator: ":")
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
