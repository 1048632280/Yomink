import Foundation
import GRDB

final class BookGroupRepository: @unchecked Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchGroupList() throws -> BookGroupList {
        guard let writer = databaseManager.writer else {
            return BookGroupList(totalBookCount: 0, ungroupedBookCount: 0, groups: [])
        }

        return try writer.read { database in
            let totalBookCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM books") ?? 0
            let ungroupedBookCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM books WHERE groupID IS NULL"
            ) ?? 0
            let groups = try Row.fetchAll(
                database,
                sql: """
                SELECT bookGroups.id, bookGroups.name, bookGroups.sortIndex,
                    bookGroups.createdAt, bookGroups.updatedAt,
                    COUNT(books.id) AS bookCount
                FROM bookGroups
                LEFT JOIN books ON books.groupID = bookGroups.id
                GROUP BY bookGroups.id
                ORDER BY bookGroups.sortIndex ASC, bookGroups.createdAt ASC
                """
            ).map(BookGroupSummary.init(databaseRow:))

            return BookGroupList(
                totalBookCount: totalBookCount,
                ungroupedBookCount: ungroupedBookCount,
                groups: groups
            )
        }
    }

    func createGroup(name: String) throws -> BookGroupRecord {
        let trimmedName = normalizedName(name)
        guard !trimmedName.isEmpty else {
            throw BookGroupRepositoryError.emptyName
        }
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        return try writer.write { database in
            let nextSortIndex = (try Int.fetchOne(
                database,
                sql: "SELECT MAX(sortIndex) FROM bookGroups"
            ) ?? -1) + 1
            let group = BookGroupRecord(name: trimmedName, sortIndex: nextSortIndex)
            try database.execute(
                sql: """
                INSERT INTO bookGroups (id, name, sortIndex, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: group.databaseArguments
            )
            return group
        }
    }

    func renameGroup(id: UUID, name: String) throws {
        let trimmedName = normalizedName(name)
        guard !trimmedName.isEmpty else {
            throw BookGroupRepositoryError.emptyName
        }
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "UPDATE bookGroups SET name = ?, updatedAt = ? WHERE id = ?",
                arguments: [trimmedName, Date().timeIntervalSince1970, id.uuidString]
            )
        }
    }

    func deleteGroup(id: UUID) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "UPDATE books SET groupID = NULL WHERE groupID = ?",
                arguments: [id.uuidString]
            )
            try database.execute(
                sql: "DELETE FROM bookGroups WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BookGroupRepositoryError: Error {
    case emptyName
}

private extension BookGroupRecord {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            name,
            sortIndex,
            createdAt.timeIntervalSince1970,
            updatedAt.timeIntervalSince1970
        ]
    }

    init(databaseRow row: Row) {
        let idString: String = row["id"]
        let createdAt: Double = row["createdAt"]
        let updatedAt: Double = row["updatedAt"]

        self.init(
            id: UUID(uuidString: idString) ?? UUID(),
            name: row["name"],
            sortIndex: row["sortIndex"],
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

private extension BookGroupSummary {
    init(databaseRow row: Row) {
        self.init(
            group: BookGroupRecord(databaseRow: row),
            bookCount: row["bookCount"]
        )
    }
}
