import CoreGraphics
import Foundation

enum ReadingTheme: String, Codable, CaseIterable {
    case paper
    case white
    case eyeCare
    case black

    var displayName: String {
        switch self {
        case .paper:
            return "\u{7EB8}\u{5F20}"
        case .white:
            return "\u{767D}\u{8272}"
        case .eyeCare:
            return "\u{62A4}\u{773C}"
        case .black:
            return "\u{9ED1}\u{8272}"
        }
    }
}

struct ReadingSettings: Hashable, Codable {
    static let fontSizeRange: ClosedRange<Double> = 14...30
    static let lineSpacingRange: ClosedRange<Double> = 2...14
    static let paragraphSpacingRange: ClosedRange<Double> = 4...18

    var layout: ReadingLayout
    var theme: ReadingTheme

    static let standard = ReadingSettings(
        layout: .defaultPhone,
        theme: .paper
    )

    func normalized(viewportSize: CGSize? = nil) -> ReadingSettings {
        var settings = self
        if let viewportSize {
            settings.layout.viewportSize = viewportSize
        }
        settings.layout.fontSize = Self.clamp(settings.layout.fontSize, in: Self.fontSizeRange)
        settings.layout.lineSpacing = Self.clamp(settings.layout.lineSpacing, in: Self.lineSpacingRange)
        settings.layout.paragraphSpacing = Self.clamp(
            settings.layout.paragraphSpacing,
            in: Self.paragraphSpacingRange
        )
        return settings
    }

    private static func clamp(_ value: CGFloat, in range: ClosedRange<Double>) -> CGFloat {
        CGFloat(min(range.upperBound, max(range.lowerBound, Double(value))))
    }
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
        return settings.normalized()
    }

    func save(_ settings: ReadingSettings) {
        guard let data = try? JSONEncoder().encode(settings.normalized()) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
