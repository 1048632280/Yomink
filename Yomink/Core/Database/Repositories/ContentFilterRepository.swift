import Foundation
import GRDB

final class ContentFilterRepository: @unchecked Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchRules(bookID: UUID) throws -> [ContentFilterRule] {
        guard let writer = databaseManager.writer else {
            return []
        }

        return try writer.read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookID, sourceText, replacementText, createdAt
                FROM contentFilterRules
                WHERE bookID = ?
                ORDER BY createdAt ASC
                """,
                arguments: [bookID.uuidString]
            ).map(ContentFilterRule.init(databaseRow:))
        }
    }

    func insertRule(bookID: UUID, sourceText: String, replacementText: String?) throws -> ContentFilterRule {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        let rule = ContentFilterRule(
            id: UUID(),
            bookID: bookID,
            sourceText: sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            replacementText: replacementText?.trimmedReplacement,
            createdAt: Date()
        )
        guard !rule.sourceText.isEmpty else {
            return rule
        }

        try writer.write { database in
            try database.execute(
                sql: """
                INSERT INTO contentFilterRules (id, bookID, sourceText, replacementText, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: rule.databaseArguments
            )
        }
        return rule
    }

    func deleteRule(_ rule: ContentFilterRule) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        try writer.write { database in
            try database.execute(
                sql: "DELETE FROM contentFilterRules WHERE id = ? AND bookID = ?",
                arguments: [rule.id.uuidString, rule.bookID.uuidString]
            )
        }
    }
}

private extension ContentFilterRule {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            bookID.uuidString,
            sourceText,
            replacementText,
            createdAt.timeIntervalSince1970
        ]
    }

    init(databaseRow row: Row) {
        let idString: String = row["id"]
        let bookIDString: String = row["bookID"]
        let createdAt: Double = row["createdAt"]
        self.init(
            id: UUID(uuidString: idString) ?? UUID(),
            bookID: UUID(uuidString: bookIDString) ?? UUID(),
            sourceText: row["sourceText"],
            replacementText: row["replacementText"],
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

private extension String {
    var trimmedReplacement: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
