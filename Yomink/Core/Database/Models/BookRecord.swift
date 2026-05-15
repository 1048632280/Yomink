import Foundation
import GRDB

struct BookRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    static let databaseTableName = "books"

    var id: UUID
    var title: String
    var author: String?
    var summary: String? = nil
    var groupID: UUID? = nil
    var filePath: String
    var encoding: TextEncoding
    var fileSize: UInt64
    var importedAt: Date
    var lastReadAt: Date?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}
