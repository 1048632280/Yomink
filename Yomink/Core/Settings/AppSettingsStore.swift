import Foundation

enum BookshelfSortMode: String, Codable, CaseIterable {
    case importedAt
    case lastReadAt

    var title: String {
        switch self {
        case .importedAt:
            return "\u{5BFC}\u{5165}\u{65F6}\u{95F4}"
        case .lastReadAt:
            return "\u{6700}\u{8FD1}\u{9605}\u{8BFB}"
        }
    }
}

final class AppSettingsStore {
    private let userDefaults: UserDefaults
    private let maximumSearchHistoryCount = 12

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var bookshelfSortMode: BookshelfSortMode {
        get {
            guard let rawValue = userDefaults.string(forKey: "bookshelfSortMode"),
                  let mode = BookshelfSortMode(rawValue: rawValue) else {
                return .lastReadAt
            }
            return mode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: "bookshelfSortMode")
        }
    }

    var bookshelfSearchHistory: [String] {
        userDefaults.stringArray(forKey: "bookshelfSearchHistory") ?? []
    }

    func rememberBookshelfSearch(_ query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return
        }

        var history = bookshelfSearchHistory.filter {
            $0.compare(normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        history.insert(normalizedQuery, at: 0)
        userDefaults.set(Array(history.prefix(maximumSearchHistoryCount)), forKey: "bookshelfSearchHistory")
    }

    func clearBookshelfSearchHistory() {
        userDefaults.removeObject(forKey: "bookshelfSearchHistory")
    }
}
