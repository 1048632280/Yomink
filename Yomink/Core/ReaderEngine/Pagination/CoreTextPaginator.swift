import CoreGraphics
import CoreText
import Foundation

enum PaginationError: Error {
    case emptyWindow
    case invalidLayout
    case windowTooLarge
}

struct PaginatedFirstPage: Hashable, Sendable {
    let pageByteRange: PageByteRange
    let text: String
    let startsAtParagraphBoundary: Bool
}

struct CoreTextPaginator {
    static let maximumUTF16Length = 120_000

    func paginateFirstPage(
        window: TextWindow,
        layout: ReadingLayout,
        bookID: UUID
    ) throws -> PageByteRange {
        try paginateFirstPageWithText(
            window: window,
            layout: layout,
            bookID: bookID,
            encoding: .utf8
        ).pageByteRange
    }

    func paginateFirstPageWithText(
        window: TextWindow,
        layout: ReadingLayout,
        bookID: UUID,
        encoding: TextEncoding,
        startsAtParagraphBoundary: Bool = true
    ) throws -> PaginatedFirstPage {
        try paginatePageWithText(
            window: window,
            layout: layout,
            bookID: bookID,
            pageIndex: 0,
            encoding: encoding,
            startsAtParagraphBoundary: startsAtParagraphBoundary
        )
    }

    func paginatePageWithText(
        window: TextWindow,
        layout: ReadingLayout,
        bookID: UUID,
        pageIndex: Int,
        encoding: TextEncoding,
        startsAtParagraphBoundary: Bool = true
    ) throws -> PaginatedFirstPage {
        guard !Thread.isMainThread else {
            assertionFailure("CoreText pagination must not run on the main thread.")
            throw PaginationError.invalidLayout
        }
        guard !window.text.isEmpty else {
            throw PaginationError.emptyWindow
        }
        guard window.text.utf16.count <= Self.maximumUTF16Length else {
            throw PaginationError.windowTooLarge
        }

        let attributedString = ReaderTextStyler.attributedText(
            for: window.text,
            layout: layout,
            startsAtParagraphBoundary: startsAtParagraphBoundary
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        let textRect = layout.contentRect(
            in: CGRect(origin: .zero, size: layout.viewportSize)
        )
        path.addRect(textRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        let visibleText = window.text.prefixUTF16Units(visibleRange.length)
        let estimatedEndOffset = estimateByteOffset(
            visibleText: visibleText,
            window: window,
            encoding: encoding
        )

        let pageByteRange = PageByteRange(
            bookID: bookID,
            pageIndex: pageIndex,
            byteRange: window.startByteOffset..<estimatedEndOffset
        )
        return PaginatedFirstPage(
            pageByteRange: pageByteRange,
            text: visibleText,
            startsAtParagraphBoundary: startsAtParagraphBoundary
        )
    }

    private func estimateByteOffset(visibleText: String, window: TextWindow, encoding: TextEncoding) -> UInt64 {
        guard !visibleText.isEmpty else {
            return window.startByteOffset
        }

        let visibleByteCount = UInt64(visibleText.data(using: encoding.stringEncoding)?.count ?? visibleText.utf8.count)
        return min(window.endByteOffset, window.startByteOffset + visibleByteCount)
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
