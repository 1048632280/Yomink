import Foundation

struct BookshelfBookItem: Hashable, Sendable {
    let book: BookRecord
    let readingProgress: Double

    var id: UUID {
        book.id
    }
}
