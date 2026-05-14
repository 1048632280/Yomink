import CoreGraphics
import Foundation

struct ReaderOpeningRequest: Hashable, Sendable {
    let bookID: UUID
    let viewportSize: CGSize
    let layout: ReadingLayout
    let preferredByteOffset: UInt64?

    init(
        bookID: UUID,
        viewportSize: CGSize,
        layout: ReadingLayout,
        preferredByteOffset: UInt64?
    ) {
        self.bookID = bookID
        self.viewportSize = viewportSize
        var resolvedLayout = layout
        resolvedLayout.viewportSize = viewportSize
        self.layout = resolvedLayout
        self.preferredByteOffset = preferredByteOffset
    }
}

