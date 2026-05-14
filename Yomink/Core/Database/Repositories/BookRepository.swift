import Foundation
import GRDB

final class BookRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchBooks() throws -> [BookRecord] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            try BookRecord
                .order(Column("lastReadAt").desc, Column("importedAt").desc)
                .fetchAll(database)
        }
    }
}

