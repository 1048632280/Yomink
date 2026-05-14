import Foundation

struct PageByteRange: Hashable, Codable {
    let bookID: UUID
    let pageIndex: Int
    let byteRange: Range<UInt64>

    var startByteOffset: UInt64 {
        byteRange.lowerBound
    }

    var endByteOffset: UInt64 {
        byteRange.upperBound
    }
}

