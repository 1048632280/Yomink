import Foundation

struct ReaderPage: Hashable, Sendable {
    let bookID: UUID
    let pageIndex: Int
    let byteRange: Range<UInt64>
    let text: String

    var startByteOffset: UInt64 {
        byteRange.lowerBound
    }

    var endByteOffset: UInt64 {
        byteRange.upperBound
    }
}

