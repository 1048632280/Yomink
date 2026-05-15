import Foundation

struct ReadingChapter: Hashable, Codable, Sendable {
    let id: UUID
    let bookID: UUID
    let title: String
    let byteOffset: UInt64
    let sortIndex: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        title: String,
        byteOffset: UInt64,
        sortIndex: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.title = title
        self.byteOffset = byteOffset
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
