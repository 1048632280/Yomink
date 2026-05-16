import CoreGraphics
import CoreText
import Foundation

enum ReaderTextStyler {
    static func attributedText(for text: String, layout: ReadingLayout, foregroundColor: CGColor? = nil) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: bodyAttributes(layout: layout, foregroundColor: foregroundColor)
        )
        applyChapterTitleStyle(to: attributedString, layout: layout, foregroundColor: foregroundColor)
        return attributedString
    }

    static func startsWithChapterTitle(_ text: String) -> Bool {
        firstLineRange(in: text).map { normalizedChapterTitle(from: String(text[$0])) != nil } ?? false
    }

    private static func bodyAttributes(
        layout: ReadingLayout,
        foregroundColor: CGColor?
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                layout.fontName as CFString,
                layout.fontSize,
                nil
            ),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(layout: layout)
        ]
        if let foregroundColor {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = foregroundColor
        }
        return attributes
    }

    private static func applyChapterTitleStyle(
        to attributedString: NSMutableAttributedString,
        layout: ReadingLayout,
        foregroundColor: CGColor?
    ) {
        let chapterTitleRanges = chapterTitleRanges(in: attributedString.string)
        guard !chapterTitleRanges.isEmpty else {
            return
        }

        let titleFontSize = layout.fontSize + 1
        let titleFont = CTFontCreateWithName(layout.fontName as CFString, titleFontSize, nil)
        let boldTitleFont = CTFontCreateCopyWithSymbolicTraits(
            titleFont,
            titleFontSize,
            nil,
            .traitBold,
            .traitBold
        ) ?? titleFont
        var titleAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): boldTitleFont,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(
                layout: layout,
                paragraphSpacingMultiplier: 1.35
            )
        ]
        if let foregroundColor {
            titleAttributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = foregroundColor
        }
        for lineRange in chapterTitleRanges {
            attributedString.addAttributes(
                titleAttributes,
                range: NSRange(lineRange, in: attributedString.string)
            )
        }
    }

    private static func firstLineRange(in text: String) -> Range<String.Index>? {
        guard !text.isEmpty else {
            return nil
        }
        let endIndex = text.firstIndex(where: \.isNewline) ?? text.endIndex
        return text.startIndex..<endIndex
    }

    private static func chapterTitleRanges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else {
            return []
        }

        var ranges: [Range<String.Index>] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: .byLines
        ) { substring, lineRange, _, _ in
            guard let substring,
                  normalizedChapterTitle(from: substring) != nil else {
                return
            }
            ranges.append(lineRange)
        }
        return ranges
    }

    private static func paragraphStyle(
        layout: ReadingLayout,
        paragraphSpacingMultiplier: CGFloat = 1
    ) -> CTParagraphStyle {
        var lineSpacing = layout.lineSpacing
        var paragraphSpacing = layout.paragraphSpacing * paragraphSpacingMultiplier
        return withUnsafePointer(to: &lineSpacing) { lineSpacingPointer in
            withUnsafePointer(to: &paragraphSpacing) { paragraphSpacingPointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(lineSpacingPointer)
                    ),
                    CTParagraphStyleSetting(
                        spec: .paragraphSpacing,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(paragraphSpacingPointer)
                    )
                ]
                return settings.withUnsafeBufferPointer { buffer in
                    CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
                }
            }
        }
    }

    private static func normalizedChapterTitle(from line: String) -> String? {
        let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.count <= 80 else {
            return nil
        }

        if specialChapterTitles.contains(title) {
            return title
        }
        if isChineseOrdinalHeading(title) || isEnglishChapterHeading(title) || isVolumeHeading(title) {
            return title
        }
        return nil
    }

    private static func isChineseOrdinalHeading(_ title: String) -> Bool {
        guard title.hasPrefix("\u{7B2C}") else {
            return false
        }

        let prefix = String(title.prefix(16))
        return headingMarkers.contains { marker in
            prefix.contains(marker)
        }
    }

    private static func isEnglishChapterHeading(_ title: String) -> Bool {
        let lowercasedTitle = title.lowercased()
        return lowercasedTitle.hasPrefix("chapter ")
            || lowercasedTitle.hasPrefix("chapter\t")
            || lowercasedTitle.hasPrefix("chapter.")
    }

    private static func isVolumeHeading(_ title: String) -> Bool {
        guard title.count <= 24 else {
            return false
        }
        return title.hasPrefix("\u{5377}") || title.hasPrefix("\u{7BC7}")
    }
}

private let headingMarkers = [
    "\u{7AE0}",
    "\u{8282}",
    "\u{56DE}",
    "\u{5377}",
    "\u{90E8}",
    "\u{7BC7}"
]

private let specialChapterTitles: Set<String> = [
    "\u{5E8F}",
    "\u{5E8F}\u{7AE0}",
    "\u{524D}\u{8A00}",
    "\u{6954}\u{5B50}",
    "\u{5F15}\u{5B50}",
    "\u{540E}\u{8BB0}",
    "\u{5C3E}\u{58F0}"
]
