import Foundation

struct ReadingBookmark: Hashable, Codable, Sendable {
    let id: UUID
    let bookID: UUID
    let title: String
    let byteOffset: UInt64
    let createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        title: String,
        byteOffset: UInt64,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.title = title
        self.byteOffset = byteOffset
        self.createdAt = createdAt
    }
}

struct ReadingBookmarkAddResult: Hashable, Sendable {
    let bookmark: ReadingBookmark
    let didCreate: Bool
}
