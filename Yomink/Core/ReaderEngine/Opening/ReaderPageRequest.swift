import Foundation

struct ReaderPageRequest: Hashable, Sendable {
    let bookID: UUID
    let startByteOffset: UInt64
    let pageIndex: Int
    let layout: ReadingLayout
}

