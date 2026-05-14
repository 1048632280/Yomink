import Foundation

struct ReadingProgress: Hashable, Codable {
    let bookID: UUID
    var byteOffset: UInt64
    var updatedAt: Date
}

