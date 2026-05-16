import CoreGraphics
import Foundation

struct ReadingLayout: Hashable, Codable, Sendable {
    var viewportSize: CGSize
    var contentInsets: CodableEdgeInsets
    var fontName: String
    var fontSize: CGFloat
    var characterSpacing: CGFloat
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var bodyFontWeight: CGFloat
    var firstLineIndent: CGFloat
    var chapterTitleCharacterSpacing: CGFloat
    var chapterTitleLineSpacing: CGFloat
    var chapterTitleParagraphSpacing: CGFloat
    var chapterTitleFontWeight: CGFloat
    var chapterTitleFontSizeDelta: CGFloat
    var widgetLayout: ReadingWidgetLayout

    static let defaultPhone = ReadingLayout(
        viewportSize: CGSize(width: 390, height: 844),
        contentInsets: CodableEdgeInsets(top: 72, left: 20, bottom: 46, right: 20),
        fontName: "PingFangSC-Regular",
        fontSize: 18,
        characterSpacing: 0,
        lineSpacing: 10,
        paragraphSpacing: 14,
        bodyFontWeight: 0,
        firstLineIndent: 2,
        chapterTitleCharacterSpacing: 0,
        chapterTitleLineSpacing: 10,
        chapterTitleParagraphSpacing: 14,
        chapterTitleFontWeight: 3,
        chapterTitleFontSizeDelta: 1,
        widgetLayout: .standard
    )

    static let compactPhone = ReadingLayout(
        viewportSize: CGSize(width: 390, height: 844),
        contentInsets: CodableEdgeInsets(top: 58, left: 18, bottom: 38, right: 18),
        fontName: "PingFangSC-Regular",
        fontSize: 18,
        characterSpacing: 0,
        lineSpacing: 8,
        paragraphSpacing: 10,
        bodyFontWeight: 0,
        firstLineIndent: 2,
        chapterTitleCharacterSpacing: 0,
        chapterTitleLineSpacing: 8,
        chapterTitleParagraphSpacing: 10,
        chapterTitleFontWeight: 3,
        chapterTitleFontSizeDelta: 1,
        widgetLayout: ReadingWidgetLayout(
            leftInset: 18,
            rightInset: 18,
            bottomInset: 22,
            titleTopInset: 36,
            titleLeftInset: 18
        )
    )

    static let loosePhone = ReadingLayout(
        viewportSize: CGSize(width: 390, height: 844),
        contentInsets: CodableEdgeInsets(top: 86, left: 24, bottom: 56, right: 24),
        fontName: "PingFangSC-Regular",
        fontSize: 18,
        characterSpacing: 0,
        lineSpacing: 12,
        paragraphSpacing: 18,
        bodyFontWeight: 0,
        firstLineIndent: 2,
        chapterTitleCharacterSpacing: 0,
        chapterTitleLineSpacing: 12,
        chapterTitleParagraphSpacing: 18,
        chapterTitleFontWeight: 3,
        chapterTitleFontSizeDelta: 2,
        widgetLayout: ReadingWidgetLayout(
            leftInset: 22,
            rightInset: 22,
            bottomInset: 30,
            titleTopInset: 48,
            titleLeftInset: 22
        )
    )

    init(
        viewportSize: CGSize,
        contentInsets: CodableEdgeInsets,
        fontName: String,
        fontSize: CGFloat,
        characterSpacing: CGFloat = 0,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        bodyFontWeight: CGFloat = 0,
        firstLineIndent: CGFloat = 2,
        chapterTitleCharacterSpacing: CGFloat = 0,
        chapterTitleLineSpacing: CGFloat? = nil,
        chapterTitleParagraphSpacing: CGFloat? = nil,
        chapterTitleFontWeight: CGFloat = 3,
        chapterTitleFontSizeDelta: CGFloat = 1,
        widgetLayout: ReadingWidgetLayout = .standard
    ) {
        self.viewportSize = viewportSize
        self.contentInsets = contentInsets
        self.fontName = fontName
        self.fontSize = fontSize
        self.characterSpacing = characterSpacing
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.bodyFontWeight = bodyFontWeight
        self.firstLineIndent = firstLineIndent
        self.chapterTitleCharacterSpacing = chapterTitleCharacterSpacing
        self.chapterTitleLineSpacing = chapterTitleLineSpacing ?? lineSpacing
        self.chapterTitleParagraphSpacing = chapterTitleParagraphSpacing ?? paragraphSpacing
        self.chapterTitleFontWeight = chapterTitleFontWeight
        self.chapterTitleFontSizeDelta = chapterTitleFontSizeDelta
        self.widgetLayout = widgetLayout
    }

    enum CodingKeys: String, CodingKey {
        case viewportSize
        case contentInsets
        case fontName
        case fontSize
        case characterSpacing
        case lineSpacing
        case paragraphSpacing
        case bodyFontWeight
        case firstLineIndent
        case chapterTitleCharacterSpacing
        case chapterTitleLineSpacing
        case chapterTitleParagraphSpacing
        case chapterTitleFontWeight
        case chapterTitleFontSizeDelta
        case widgetLayout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultPhone
        viewportSize = try container.decodeIfPresent(CGSize.self, forKey: .viewportSize) ?? defaults.viewportSize
        contentInsets = try container.decodeIfPresent(CodableEdgeInsets.self, forKey: .contentInsets)
            ?? defaults.contentInsets
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? defaults.fontName
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? defaults.fontSize
        characterSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .characterSpacing)
            ?? defaults.characterSpacing
        lineSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        paragraphSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .paragraphSpacing)
            ?? defaults.paragraphSpacing
        bodyFontWeight = try container.decodeIfPresent(CGFloat.self, forKey: .bodyFontWeight)
            ?? defaults.bodyFontWeight
        firstLineIndent = try container.decodeIfPresent(CGFloat.self, forKey: .firstLineIndent)
            ?? defaults.firstLineIndent
        chapterTitleCharacterSpacing = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .chapterTitleCharacterSpacing
        ) ?? characterSpacing
        chapterTitleLineSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .chapterTitleLineSpacing)
            ?? lineSpacing
        chapterTitleParagraphSpacing = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .chapterTitleParagraphSpacing
        ) ?? paragraphSpacing
        chapterTitleFontWeight = try container.decodeIfPresent(CGFloat.self, forKey: .chapterTitleFontWeight)
            ?? defaults.chapterTitleFontWeight
        chapterTitleFontSizeDelta = try container.decodeIfPresent(CGFloat.self, forKey: .chapterTitleFontSizeDelta)
            ?? defaults.chapterTitleFontSizeDelta
        widgetLayout = try container.decodeIfPresent(ReadingWidgetLayout.self, forKey: .widgetLayout)
            ?? defaults.widgetLayout
    }

    func contentRect(in bounds: CGRect) -> CGRect {
        // CoreText pagination and drawing both use the flipped bottom-left coordinate space.
        CGRect(
            x: contentInsets.left,
            y: contentInsets.bottom,
            width: max(1, bounds.width - contentInsets.left - contentInsets.right),
            height: max(1, bounds.height - contentInsets.top - contentInsets.bottom)
        )
    }
}

struct CodableEdgeInsets: Hashable, Codable, Sendable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat
}

struct ReadingWidgetLayout: Hashable, Codable, Sendable {
    var leftInset: CGFloat
    var rightInset: CGFloat
    var bottomInset: CGFloat
    var titleTopInset: CGFloat
    var titleLeftInset: CGFloat

    static let standard = ReadingWidgetLayout(
        leftInset: 20,
        rightInset: 20,
        bottomInset: 27,
        titleTopInset: 43,
        titleLeftInset: 20
    )
}
