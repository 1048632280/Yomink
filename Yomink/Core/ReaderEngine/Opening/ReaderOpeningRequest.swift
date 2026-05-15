import CoreGraphics
import Foundation

struct ReaderOpeningRequest: Hashable, Sendable {
    let bookID: UUID
    let viewportSize: CGSize
    let layout: ReadingLayout
    let preferredByteOffset: UInt64?
    let upperBoundByteOffset: UInt64?

    init(
        bookID: UUID,
        viewportSize: CGSize,
        layout: ReadingLayout,
        preferredByteOffset: UInt64?,
        upperBoundByteOffset: UInt64? = nil
    ) {
        self.bookID = bookID
        self.viewportSize = viewportSize
        var resolvedLayout = layout
        resolvedLayout.viewportSize = viewportSize
        self.layout = resolvedLayout
        self.preferredByteOffset = preferredByteOffset
        self.upperBoundByteOffset = upperBoundByteOffset
    }
}
