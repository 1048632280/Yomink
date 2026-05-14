import Foundation

enum ReadingTheme: String, Codable, CaseIterable {
    case paper
    case white
    case eyeCare
    case black
}

struct ReadingSettings: Hashable, Codable {
    var layout: ReadingLayout
    var theme: ReadingTheme

    static let standard = ReadingSettings(
        layout: .defaultPhone,
        theme: .paper
    )
}

final class ReadingSettingsStore {
    private let userDefaults: UserDefaults
    private let key = "readingSettings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> ReadingSettings {
        guard let data = userDefaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ReadingSettings.self, from: data) else {
            return .standard
        }
        return settings
    }

    func save(_ settings: ReadingSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}

