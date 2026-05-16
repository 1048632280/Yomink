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

enum ChapterParseStatus: Hashable, Sendable {
    case notStarted
    case parsing(scannedUntilByteOffset: UInt64, fileSize: UInt64)
    case completed
    case failed(String)
}

struct ChapterParseState: Hashable, Sendable {
    let bookID: UUID
    let scannedUntilByteOffset: UInt64
    let fileSize: UInt64
    let nextSortIndex: Int
    let updatedAt: Date
    let completedAt: Date?
    let failureReason: String?

    var isCompleted: Bool {
        completedAt != nil
    }

    var status: ChapterParseStatus {
        if let failureReason, !failureReason.isEmpty {
            return .failed(failureReason)
        }
        if isCompleted {
            return .completed
        }
        return .parsing(
            scannedUntilByteOffset: scannedUntilByteOffset,
            fileSize: fileSize
        )
    }
}

struct ChapterCatalogSnapshot: Hashable, Sendable {
    let chapters: [ReadingChapter]
    let state: ChapterParseState?

    var status: ChapterParseStatus {
        state?.status ?? .notStarted
    }
}
