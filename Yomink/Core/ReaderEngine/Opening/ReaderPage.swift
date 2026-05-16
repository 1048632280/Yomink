import Foundation

struct ReaderPage: Hashable, Sendable {
    let bookID: UUID
    let pageIndex: Int
    let byteRange: Range<UInt64>
    let text: String
    let startsAtParagraphBoundary: Bool

    init(
        bookID: UUID,
        pageIndex: Int,
        byteRange: Range<UInt64>,
        text: String,
        startsAtParagraphBoundary: Bool = true
    ) {
        self.bookID = bookID
        self.pageIndex = pageIndex
        self.byteRange = byteRange
        self.text = text
        self.startsAtParagraphBoundary = startsAtParagraphBoundary
    }

    var startByteOffset: UInt64 {
        byteRange.lowerBound
    }

    var endByteOffset: UInt64 {
        byteRange.upperBound
    }
}
