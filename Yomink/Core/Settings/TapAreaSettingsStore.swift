import Foundation
import GRDB

enum ReaderTapAreaAction: String, CaseIterable, Codable, Sendable {
    case previousPage
    case nextPage
    case toggleMenu

    var displayName: String {
        switch self {
        case .previousPage:
            return "\u{4E0A}\u{4E00}\u{9875}"
        case .nextPage:
            return "\u{4E0B}\u{4E00}\u{9875}"
        case .toggleMenu:
            return "\u{83DC}\u{5355}"
        }
    }
}

struct TapAreaSettings: Hashable, Sendable {
    static let areaCount = 9

    var actions: [ReaderTapAreaAction]

    static let standard = TapAreaSettings(actions: [
        .previousPage, .toggleMenu, .nextPage,
        .previousPage, .toggleMenu, .nextPage,
        .previousPage, .toggleMenu, .nextPage
    ])

    func action(for areaIndex: Int) -> ReaderTapAreaAction {
        guard actions.indices.contains(areaIndex) else {
            return .toggleMenu
        }
        return actions[areaIndex]
    }

    mutating func setAction(_ action: ReaderTapAreaAction, for areaIndex: Int) {
        guard actions.indices.contains(areaIndex) else {
            return
        }
        actions[areaIndex] = action
    }
}

final class TapAreaSettingsStore: @unchecked Sendable {
    private static let globalScopeID = "global"

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func load(bookID: UUID?) throws -> TapAreaSettings {
        guard let writer = databaseManager.writer else {
            return .standard
        }

        let scopeID = bookID?.uuidString ?? Self.globalScopeID
        return try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT areaIndex, action
                FROM tapAreaSettings
                WHERE scopeID = ?
                ORDER BY areaIndex ASC
                """,
                arguments: [scopeID]
            )
            var settings = TapAreaSettings.standard
            for row in rows {
                let areaIndex: Int = row["areaIndex"]
                let actionRawValue: String = row["action"]
                if let action = ReaderTapAreaAction(rawValue: actionRawValue) {
                    settings.setAction(action, for: areaIndex)
                }
            }
            return settings
        }
    }

    func save(_ settings: TapAreaSettings, bookID: UUID?) throws {
        guard let writer = databaseManager.writer else {
            throw BookRepositoryError.databaseUnavailable
        }

        let scopeID = bookID?.uuidString ?? Self.globalScopeID
        try writer.write { database in
            for areaIndex in 0..<TapAreaSettings.areaCount {
                let action = settings.action(for: areaIndex)
                try database.execute(
                    sql: """
                    INSERT INTO tapAreaSettings (scopeID, areaIndex, action, updatedAt)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(scopeID, areaIndex) DO UPDATE SET
                        action = excluded.action,
                        updatedAt = excluded.updatedAt
                    """,
                    arguments: [
                        scopeID,
                        areaIndex,
                        action.rawValue,
                        Date().timeIntervalSince1970
                    ]
                )
            }
        }
    }
}
