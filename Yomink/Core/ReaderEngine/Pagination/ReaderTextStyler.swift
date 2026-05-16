import CoreGraphics
import CoreText
import Foundation

enum ReaderTextStyler {
    static func attributedText(
        for text: String,
        layout: ReadingLayout,
        foregroundColor: CGColor? = nil,
        startsAtParagraphBoundary: Bool = true
    ) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: bodyAttributes(layout: layout, foregroundColor: foregroundColor)
        )
        applyBodyParagraphStyle(
            to: attributedString,
            layout: layout,
            startsAtParagraphBoundary: startsAtParagraphBoundary
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
            NSAttributedString.Key(kCTFontAttributeName as String): font(
                name: layout.fontName,
                size: layout.fontSize,
                weight: layout.bodyFontWeight
            ),
            NSAttributedString.Key(kCTKernAttributeName as String): layout.characterSpacing,
            NSAttributedString.Key(kCTLanguageAttributeName as String): "zh-Hans"
        ]
        if let foregroundColor {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = foregroundColor
        }
        return attributes
    }

    private static func applyBodyParagraphStyle(
        to attributedString: NSMutableAttributedString,
        layout: ReadingLayout,
        startsAtParagraphBoundary: Bool
    ) {
        for (index, paragraphRange) in paragraphRanges(in: attributedString.string).enumerated() {
            let isContinuation = index == 0 && !startsAtParagraphBoundary
            let firstLineIndent = isContinuation || paragraphHasSourceIndent(
                in: attributedString.string,
                range: paragraphRange
            )
                ? 0
                : layout.firstLineIndent * layout.fontSize
            attributedString.addAttributes(
                [
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(
                        lineSpacing: layout.lineSpacing,
                        paragraphSpacing: layout.paragraphSpacing,
                        firstLineIndent: firstLineIndent,
                        alignment: .justified,
                        lineBreakMode: .byWordWrapping
                    )
                ],
                range: NSRange(paragraphRange, in: attributedString.string)
            )
        }
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

        let titleFontSize = layout.fontSize + layout.chapterTitleFontSizeDelta
        var titleAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(
                name: layout.fontName,
                size: titleFontSize,
                weight: layout.chapterTitleFontWeight
            ),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(
                lineSpacing: layout.chapterTitleLineSpacing,
                paragraphSpacing: layout.chapterTitleParagraphSpacing,
                firstLineIndent: 0,
                alignment: .left,
                lineBreakMode: .byWordWrapping
            ),
            NSAttributedString.Key(kCTKernAttributeName as String): layout.chapterTitleCharacterSpacing,
            NSAttributedString.Key(kCTLanguageAttributeName as String): "zh-Hans"
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

    private static func paragraphRanges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else {
            return []
        }

        var ranges: [Range<String.Index>] = []
        var startIndex = text.startIndex
        while startIndex < text.endIndex {
            if let newlineIndex = text[startIndex..<text.endIndex].firstIndex(where: \.isNewline) {
                let endIndex = text.index(after: newlineIndex)
                ranges.append(startIndex..<endIndex)
                startIndex = endIndex
            } else {
                ranges.append(startIndex..<text.endIndex)
                startIndex = text.endIndex
            }
        }
        return ranges
    }

    private static func paragraphHasSourceIndent(in text: String, range: Range<String.Index>) -> Bool {
        guard let firstCharacter = text[range].first,
              !firstCharacter.isNewline else {
            return false
        }
        return firstCharacter.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespaces.contains(scalar) || scalar.value == 0x3000
        }
    }

    private static func font(name: String, size: CGFloat, weight: CGFloat) -> CTFont {
        let baseFont = CTFontCreateWithName(name as CFString, size, nil)
        guard weight > 0 else {
            return baseFont
        }
        return CTFontCreateCopyWithSymbolicTraits(
            baseFont,
            size,
            nil,
            .traitBold,
            .traitBold
        ) ?? baseFont
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        firstLineIndent: CGFloat,
        alignment: CTTextAlignment,
        lineBreakMode: CTLineBreakMode
    ) -> CTParagraphStyle {
        var resolvedLineSpacing = lineSpacing
        var resolvedParagraphSpacing = paragraphSpacing
        var resolvedFirstLineIndent = firstLineIndent
        var resolvedAlignment = alignment
        var resolvedLineBreakMode = lineBreakMode
        return withUnsafePointer(to: &resolvedLineSpacing) { lineSpacingPointer in
            withUnsafePointer(to: &resolvedParagraphSpacing) { paragraphSpacingPointer in
                withUnsafePointer(to: &resolvedFirstLineIndent) { firstLineIndentPointer in
                    withUnsafePointer(to: &resolvedAlignment) { alignmentPointer in
                        withUnsafePointer(to: &resolvedLineBreakMode) { lineBreakModePointer in
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
                                ),
                                CTParagraphStyleSetting(
                                    spec: .firstLineHeadIndent,
                                    valueSize: MemoryLayout<CGFloat>.size,
                                    value: UnsafeRawPointer(firstLineIndentPointer)
                                ),
                                CTParagraphStyleSetting(
                                    spec: .alignment,
                                    valueSize: MemoryLayout<CTTextAlignment>.size,
                                    value: UnsafeRawPointer(alignmentPointer)
                                ),
                                CTParagraphStyleSetting(
                                    spec: .lineBreakMode,
                                    valueSize: MemoryLayout<CTLineBreakMode>.size,
                                    value: UnsafeRawPointer(lineBreakModePointer)
                                )
                            ]
                            return settings.withUnsafeBufferPointer { buffer in
                                CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
                            }
                        }
                    }
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
