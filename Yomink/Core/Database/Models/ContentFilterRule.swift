import Foundation

struct ContentFilterRule: Hashable, Sendable {
    static let databaseTableName = "contentFilterRules"

    var id: UUID
    var bookID: UUID
    var sourceText: String
    var replacementText: String?
    var createdAt: Date
}
