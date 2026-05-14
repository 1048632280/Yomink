import Foundation

enum BookshelfSortMode: String, Codable {
    case importedAt
    case lastReadAt
}

final class AppSettingsStore {
    private let userDefaults: UserDefaults

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
}

