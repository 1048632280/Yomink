import Foundation

struct ReadingProgress: Hashable, Codable, Sendable {
    let bookID: UUID
    var byteOffset: UInt64
    var updatedAt: Date
}
