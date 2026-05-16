import Foundation

enum ReaderPagingError: Error {
    case bookNotFound
    case emptyVisiblePage
    case stalledPageBoundary
}

final class ReaderPagingService: @unchecked Sendable {
    private static let previousPageSearchLength = BookFileMapping.maximumWindowLength

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
            let requestedUpperBound = request.upperBoundByteOffset.map {
                min(mapping.fileSize, max(request.startByteOffset + 1, $0))
            } ?? mapping.fileSize
            let page = try Self.makePage(
                book: book,
                mapping: mapping,
                startByteOffset: request.startByteOffset,
                upperBound: min(
                    requestedUpperBound,
                    request.startByteOffset + BookFileMapping.maximumWindowLength
                ),
                pageIndex: request.pageIndex,
                layout: request.layout
            )

            pageCache.insert(page, for: key)
            return page
        }.value
    }

    func previousPage(_ request: ReaderPreviousPageRequest) async throws -> ReaderPage? {
        let key = cacheKey(for: request)
        if let cachedPage = pageCache.readerPage(for: key) {
            return cachedPage
        }

        return try await Task.detached(priority: .userInitiated) { [bookRepository, pageCache] in
            guard let book = try bookRepository.fetchBook(id: request.bookID) else {
                throw ReaderPagingError.bookNotFound
            }

            let mapping = try BookFileMapping(fileURL: book.fileURL)
            let targetEndByteOffset = min(request.endByteOffset, mapping.fileSize)
            guard targetEndByteOffset > 0 else {
                return nil
            }

            let lowerSearchLimit = min(request.lowerBoundByteOffset ?? 0, targetEndByteOffset - 1)
            var lowerBound = targetEndByteOffset > Self.previousPageSearchLength
                ? targetEndByteOffset - Self.previousPageSearchLength
                : 0
            lowerBound = max(lowerBound, lowerSearchLimit)
            var upperBound = targetEndByteOffset - 1
            var candidatePage: ReaderPage?

            // Reverse paging is anchored at the current page start. A bounded binary search finds the earliest
            // byte offset whose text still fits in one page, avoiding global pagination after chapter/progress jumps.
            while lowerBound <= upperBound {
                let midpoint = lowerBound + (upperBound - lowerBound) / 2
                guard let page = try Self.makePageIfReadable(
                    book: book,
                    mapping: mapping,
                    startByteOffset: midpoint,
                    upperBound: targetEndByteOffset,
                    pageIndex: request.pageIndex,
                    layout: request.layout
                ) else {
                    if midpoint == 0 {
                        break
                    }
                    upperBound = midpoint - 1
                    continue
                }

                if page.endByteOffset >= targetEndByteOffset {
                    candidatePage = page
                    if midpoint == 0 {
                        break
                    }
                    upperBound = midpoint - 1
                } else {
                    lowerBound = midpoint + 1
                }
            }

            guard let candidatePage,
                  candidatePage.startByteOffset < targetEndByteOffset else {
                return nil
            }

            let page = ReaderPage(
                bookID: candidatePage.bookID,
                pageIndex: request.pageIndex,
                byteRange: candidatePage.startByteOffset..<targetEndByteOffset,
                text: candidatePage.text
            )
            pageCache.insert(page, for: key)
            return page
        }.value
    }

    private func cacheKey(for request: ReaderPageRequest) -> String {
        [
            "next",
            request.bookID.uuidString,
            "\(request.startByteOffset)",
            "\(request.pageIndex)",
            Self.cacheFingerprint(for: request.layout),
            "\(request.upperBoundByteOffset ?? 0)"
        ].joined(separator: ":")
    }

    private func cacheKey(for request: ReaderPreviousPageRequest) -> String {
        [
            "previous",
            request.bookID.uuidString,
            "\(request.endByteOffset)",
            "\(request.pageIndex)",
            Self.cacheFingerprint(for: request.layout),
            "\(request.lowerBoundByteOffset ?? 0)"
        ].joined(separator: ":")
    }

    private static func cacheFingerprint(for layout: ReadingLayout) -> String {
        [
            "\(Int(layout.viewportSize.width))x\(Int(layout.viewportSize.height))",
            layout.fontName,
            "\(layout.fontSize)",
            "\(layout.characterSpacing)",
            "\(layout.lineSpacing)",
            "\(layout.paragraphSpacing)",
            "\(layout.bodyFontWeight)",
            "\(layout.firstLineIndent)",
            "\(layout.chapterTitleCharacterSpacing)",
            "\(layout.chapterTitleLineSpacing)",
            "\(layout.chapterTitleParagraphSpacing)",
            "\(layout.chapterTitleFontWeight)",
            "\(layout.chapterTitleFontSizeDelta)",
            "\(layout.contentInsets.top)",
            "\(layout.contentInsets.left)",
            "\(layout.contentInsets.bottom)",
            "\(layout.contentInsets.right)"
        ].joined(separator: ":")
    }

    private static func makePage(
        book: BookRecord,
        mapping: BookFileMapping,
        startByteOffset: UInt64,
        upperBound: UInt64,
        pageIndex: Int,
        layout: ReadingLayout
    ) throws -> ReaderPage {
        let clampedStart = min(startByteOffset, mapping.fileSize - 1)
        let clampedUpperBound = min(mapping.fileSize, max(clampedStart + 1, upperBound))
        let windowData = try mapping.bytes(in: clampedStart..<clampedUpperBound)
        let decodedWindow = try TextDecoder().decodeBoundedWindow(data: windowData, encoding: book.encoding)
        let windowStart = clampedStart + decodedWindow.trimmedPrefixByteCount
        let windowEnd = clampedUpperBound - decodedWindow.trimmedSuffixByteCount
        let textWindow = TextWindow(
            byteRange: windowStart..<windowEnd,
            text: decodedWindow.text.prefixUTF16Units(CoreTextPaginator.maximumUTF16Length)
        )
        let pagination = try CoreTextPaginator().paginatePageWithText(
            window: textWindow,
            layout: layout,
            bookID: book.id,
            pageIndex: pageIndex,
            encoding: book.encoding
        )

        guard !pagination.text.isEmpty else {
            throw ReaderPagingError.emptyVisiblePage
        }
        guard pagination.pageByteRange.endByteOffset > pagination.pageByteRange.startByteOffset else {
            throw ReaderPagingError.stalledPageBoundary
        }

        return ReaderPage(
            bookID: book.id,
            pageIndex: pageIndex,
            byteRange: pagination.pageByteRange.byteRange,
            text: pagination.text
        )
    }

    private static func makePageIfReadable(
        book: BookRecord,
        mapping: BookFileMapping,
        startByteOffset: UInt64,
        upperBound: UInt64,
        pageIndex: Int,
        layout: ReadingLayout
    ) throws -> ReaderPage? {
        do {
            return try makePage(
                book: book,
                mapping: mapping,
                startByteOffset: startByteOffset,
                upperBound: upperBound,
                pageIndex: pageIndex,
                layout: layout
            )
        } catch TextDecoderError.undecodableWindow {
            return nil
        } catch ReaderPagingError.emptyVisiblePage {
            return nil
        }
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
