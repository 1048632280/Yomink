import CoreGraphics
import Foundation

enum ReadingTheme: String, Codable, CaseIterable, Sendable {
    case paper
    case white
    case eyeCare
    case black

    var displayName: String {
        switch self {
        case .paper:
            return "\u{7F8A}\u{76AE}\u{7EB8}"
        case .white:
            return "\u{7EAF}\u{767D}"
        case .eyeCare:
            return "\u{62A4}\u{773C}"
        case .black:
            return "\u{6DF1}\u{9083}\u{9ED1}"
        }
    }
}

enum ReadingPageTurnMode: String, Codable, CaseIterable, Sendable {
    case horizontal
    case simulatedCurl
    case verticalScroll

    var displayName: String {
        switch self {
        case .horizontal:
            return "\u{5DE6}\u{53F3}\u{5E73}\u{79FB}"
        case .simulatedCurl:
            return "\u{4EFF}\u{771F}\u{7FFB}\u{9875}"
        case .verticalScroll:
            return "\u{4E0A}\u{4E0B}\u{6ED1}\u{52A8}"
        }
    }
}

enum ReadingLayoutDensity: String, Codable, CaseIterable, Sendable {
    case compact
    case standard
    case loose
    case custom

    var displayName: String {
        switch self {
        case .compact:
            return "\u{7D27}\u{51D1}"
        case .standard:
            return "\u{6807}\u{51C6}"
        case .loose:
            return "\u{5BBD}\u{677E}"
        case .custom:
            return "\u{81EA}\u{5B9A}\u{4E49}"
        }
    }
}

enum ReadingStatusBarItem: String, Codable, CaseIterable, Hashable, Sendable {
    case time
    case battery
    case batteryPercent
    case chapterTitle
    case chapterPageProgress
    case bookProgress

    var displayName: String {
        switch self {
        case .time:
            return "\u{65F6}\u{95F4}"
        case .battery:
            return "\u{7535}\u{6C60}"
        case .batteryPercent:
            return "\u{7535}\u{91CF}"
        case .chapterTitle:
            return "\u{7AE0}\u{8282}\u{6807}\u{9898}"
        case .chapterPageProgress:
            return "\u{7AE0}\u{8282}\u{9875}\u{8FDB}\u{5EA6}"
        case .bookProgress:
            return "\u{5168}\u{4E66}\u{767E}\u{5206}\u{6BD4}"
        }
    }
}

struct ReadingSettings: Hashable, Codable, Sendable {
    static let fontSizeRange: ClosedRange<Double> = 14...30
    static let characterSpacingRange: ClosedRange<Double> = 0...4
    static let lineSpacingRange: ClosedRange<Double> = 2...18
    static let paragraphSpacingRange: ClosedRange<Double> = 4...24
    static let horizontalInsetRange: ClosedRange<Double> = 12...56
    static let verticalInsetRange: ClosedRange<Double> = 20...96
    static let fontWeightRange: ClosedRange<Double> = 0...5
    static let firstLineIndentRange: ClosedRange<Double> = 0...4
    static let titleFontSizeDeltaRange: ClosedRange<Double> = 0...4
    static let widgetHorizontalInsetRange: ClosedRange<Double> = 12...56
    static let widgetBottomInsetRange: ClosedRange<Double> = 0...48
    static let widgetTitleTopInsetRange: ClosedRange<Double> = 24...72

    var layout: ReadingLayout
    var theme: ReadingTheme
    var pageTurnMode: ReadingPageTurnMode
    var layoutDensity: ReadingLayoutDensity
    var keepScreenAwake: Bool
    var autoHideHomeIndicator: Bool
    var allowsSwipeBack: Bool
    var statusBarItems: Set<ReadingStatusBarItem>

    static let standard = ReadingSettings(
        layout: .defaultPhone,
        theme: .paper,
        pageTurnMode: .horizontal,
        layoutDensity: .standard,
        keepScreenAwake: false,
        autoHideHomeIndicator: false,
        allowsSwipeBack: false,
        statusBarItems: []
    )

    init(
        layout: ReadingLayout,
        theme: ReadingTheme,
        pageTurnMode: ReadingPageTurnMode,
        layoutDensity: ReadingLayoutDensity,
        keepScreenAwake: Bool,
        autoHideHomeIndicator: Bool,
        allowsSwipeBack: Bool,
        statusBarItems: Set<ReadingStatusBarItem>
    ) {
        self.layout = layout
        self.theme = theme
        self.pageTurnMode = pageTurnMode
        self.layoutDensity = layoutDensity
        self.keepScreenAwake = keepScreenAwake
        self.autoHideHomeIndicator = autoHideHomeIndicator
        self.allowsSwipeBack = allowsSwipeBack
        self.statusBarItems = statusBarItems
    }

    enum CodingKeys: String, CodingKey {
        case layout
        case theme
        case pageTurnMode
        case layoutDensity
        case keepScreenAwake
        case autoHideHomeIndicator
        case allowsSwipeBack
        case statusBarItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.standard
        layout = try container.decodeIfPresent(ReadingLayout.self, forKey: .layout) ?? defaults.layout
        theme = try container.decodeIfPresent(ReadingTheme.self, forKey: .theme) ?? defaults.theme
        pageTurnMode = try container.decodeIfPresent(
            ReadingPageTurnMode.self,
            forKey: .pageTurnMode
        ) ?? defaults.pageTurnMode
        layoutDensity = try container.decodeIfPresent(
            ReadingLayoutDensity.self,
            forKey: .layoutDensity
        ) ?? (layout == defaults.layout ? defaults.layoutDensity : .custom)
        keepScreenAwake = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? false
        autoHideHomeIndicator = try container.decodeIfPresent(Bool.self, forKey: .autoHideHomeIndicator) ?? false
        allowsSwipeBack = try container.decodeIfPresent(Bool.self, forKey: .allowsSwipeBack) ?? false
        statusBarItems = try container.decodeIfPresent(
            Set<ReadingStatusBarItem>.self,
            forKey: .statusBarItems
        ) ?? []
    }

    func normalized(viewportSize: CGSize? = nil) -> ReadingSettings {
        var settings = self
        settings.applyPresetLayoutIfNeeded()
        if let viewportSize {
            settings.layout.viewportSize = viewportSize
        }
        settings.layout.fontSize = Self.clamp(settings.layout.fontSize, in: Self.fontSizeRange)
        settings.layout.characterSpacing = Self.clamp(
            settings.layout.characterSpacing,
            in: Self.characterSpacingRange
        )
        settings.layout.lineSpacing = Self.clamp(settings.layout.lineSpacing, in: Self.lineSpacingRange)
        settings.layout.paragraphSpacing = Self.clamp(
            settings.layout.paragraphSpacing,
            in: Self.paragraphSpacingRange
        )
        settings.layout.bodyFontWeight = Self.clamp(settings.layout.bodyFontWeight, in: Self.fontWeightRange)
        settings.layout.firstLineIndent = Self.clamp(
            settings.layout.firstLineIndent,
            in: Self.firstLineIndentRange
        )
        settings.layout.chapterTitleCharacterSpacing = Self.clamp(
            settings.layout.chapterTitleCharacterSpacing,
            in: Self.characterSpacingRange
        )
        settings.layout.chapterTitleLineSpacing = Self.clamp(
            settings.layout.chapterTitleLineSpacing,
            in: Self.lineSpacingRange
        )
        settings.layout.chapterTitleParagraphSpacing = Self.clamp(
            settings.layout.chapterTitleParagraphSpacing,
            in: Self.paragraphSpacingRange
        )
        settings.layout.chapterTitleFontWeight = Self.clamp(
            settings.layout.chapterTitleFontWeight,
            in: Self.fontWeightRange
        )
        settings.layout.chapterTitleFontSizeDelta = Self.clamp(
            settings.layout.chapterTitleFontSizeDelta,
            in: Self.titleFontSizeDeltaRange
        )
        settings.layout.contentInsets.left = Self.clamp(
            settings.layout.contentInsets.left,
            in: Self.horizontalInsetRange
        )
        settings.layout.contentInsets.right = Self.clamp(
            settings.layout.contentInsets.right,
            in: Self.horizontalInsetRange
        )
        settings.layout.contentInsets.top = Self.clamp(
            settings.layout.contentInsets.top,
            in: Self.verticalInsetRange
        )
        settings.layout.contentInsets.bottom = Self.clamp(
            settings.layout.contentInsets.bottom,
            in: Self.verticalInsetRange
        )
        settings.layout.widgetLayout.leftInset = Self.clamp(
            settings.layout.widgetLayout.leftInset,
            in: Self.widgetHorizontalInsetRange
        )
        settings.layout.widgetLayout.rightInset = Self.clamp(
            settings.layout.widgetLayout.rightInset,
            in: Self.widgetHorizontalInsetRange
        )
        settings.layout.widgetLayout.bottomInset = Self.clamp(
            settings.layout.widgetLayout.bottomInset,
            in: Self.widgetBottomInsetRange
        )
        settings.layout.widgetLayout.titleTopInset = Self.clamp(
            settings.layout.widgetLayout.titleTopInset,
            in: Self.widgetTitleTopInsetRange
        )
        settings.layout.widgetLayout.titleLeftInset = Self.clamp(
            settings.layout.widgetLayout.titleLeftInset,
            in: Self.widgetHorizontalInsetRange
        )
        return settings
    }

    private static func clamp(_ value: CGFloat, in range: ClosedRange<Double>) -> CGFloat {
        CGFloat(min(range.upperBound, max(range.lowerBound, Double(value))))
    }
}

private extension ReadingSettings {
    mutating func applyPresetLayoutIfNeeded() {
        let fontSize = layout.fontSize
        switch layoutDensity {
        case .compact:
            layout = .compactPhone
        case .standard:
            layout = .defaultPhone
        case .loose:
            layout = .loosePhone
        case .custom:
            return
        }
        layout.fontSize = fontSize
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
