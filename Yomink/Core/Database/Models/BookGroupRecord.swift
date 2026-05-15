import Foundation

struct BookGroupRecord: Hashable, Sendable {
    var id: UUID
    var name: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sortIndex: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct BookGroupSummary: Hashable, Sendable {
    let group: BookGroupRecord
    let bookCount: Int
}

struct BookGroupList: Hashable, Sendable {
    let totalBookCount: Int
    let ungroupedBookCount: Int
    let groups: [BookGroupSummary]
}
