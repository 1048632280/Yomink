import Foundation

struct ReaderPageRequest: Hashable, Sendable {
    let bookID: UUID
    let startByteOffset: UInt64
    let pageIndex: Int
    let layout: ReadingLayout
}

struct ReaderPreviousPageRequest: Hashable, Sendable {
    let bookID: UUID
    let endByteOffset: UInt64
    let pageIndex: Int
    let layout: ReadingLayout
}
