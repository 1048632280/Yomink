import Foundation

struct ChapterCandidate: Hashable, Codable, Sendable {
    let title: String
    let byteOffset: UInt64
}

final class ChapterParser: @unchecked Sendable {
    static let maximumWindowLength: UInt64 = 256 * 1024
    static let overlapLength: UInt64 = 512
    private static let maximumCandidateLineByteLength = 320

    func parseCandidates(
        in data: Data,
        byteRange: Range<UInt64>,
        encoding: TextEncoding,
        isFinalWindow: Bool = true
    ) throws -> [ChapterCandidate] {
        guard !data.isEmpty else {
            return []
        }

        var candidates: [ChapterCandidate] = []
        var lineStart = data.startIndex
        var currentIndex = data.startIndex
        var isFirstLine = true

        // Catalog parsing stays byte-oriented so large files do not create a full-window String.
        while currentIndex < data.endIndex {
            if let lineBreakLength = Self.lineBreakLength(in: data, at: currentIndex, encoding: encoding) {
                appendCandidate(
                    from: lineStart..<currentIndex,
                    data: data,
                    byteRange: byteRange,
                    encoding: encoding,
                    isFirstLine: isFirstLine,
                    candidates: &candidates
                )

                currentIndex = data.index(
                    currentIndex,
                    offsetBy: lineBreakLength,
                    limitedBy: data.endIndex
                ) ?? data.endIndex
                lineStart = currentIndex
                isFirstLine = false
            } else {
                currentIndex = data.index(after: currentIndex)
            }
        }

        if lineStart < data.endIndex,
           isFinalWindow {
            appendCandidate(
                from: lineStart..<data.endIndex,
                data: data,
                byteRange: byteRange,
                encoding: encoding,
                isFirstLine: isFirstLine,
                candidates: &candidates
            )
        }

        return candidates
    }

    private func appendCandidate(
        from lineRange: Range<Data.Index>,
        data: Data,
        byteRange: Range<UInt64>,
        encoding: TextEncoding,
        isFirstLine: Bool,
        candidates: inout [ChapterCandidate]
    ) {
        guard !(byteRange.lowerBound > 0 && isFirstLine),
              !lineRange.isEmpty,
              data.distance(from: lineRange.lowerBound, to: lineRange.upperBound)
                <= Self.maximumCandidateLineByteLength else {
            return
        }

        let lineData = Data(data[lineRange])
        guard let line = String(data: lineData, encoding: encoding.stringEncoding),
              let title = Self.normalizedChapterTitle(from: line) else {
            return
        }

        let lineOffset = UInt64(data.distance(from: data.startIndex, to: lineRange.lowerBound))
        candidates.append(
            ChapterCandidate(
                title: title,
                byteOffset: byteRange.lowerBound + lineOffset
            )
        )
    }

    private static func normalizedChapterTitle(from line: String) -> String? {
        var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.first == Character("\u{feff}") {
            title.removeFirst()
        }
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

    private static func lineBreakLength(
        in data: Data,
        at index: Data.Index,
        encoding: TextEncoding
    ) -> Int? {
        switch encoding {
        case .utf16LittleEndian:
            guard let scalar = utf16LittleEndianScalar(in: data, at: index),
                  scalar == carriageReturn || scalar == lineFeed else {
                return nil
            }
            let nextScalarIndex = data.index(index, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
            let isCRLF = scalar == carriageReturn
                && utf16LittleEndianScalar(in: data, at: nextScalarIndex) == lineFeed
            return isCRLF ? 4 : 2
        case .utf16BigEndian:
            guard let scalar = utf16BigEndianScalar(in: data, at: index),
                  scalar == carriageReturn || scalar == lineFeed else {
                return nil
            }
            let nextScalarIndex = data.index(index, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
            let isCRLF = scalar == carriageReturn
                && utf16BigEndianScalar(in: data, at: nextScalarIndex) == lineFeed
            return isCRLF ? 4 : 2
        default:
            let byte = data[index]
            if byte == carriageReturn {
                let nextIndex = data.index(after: index)
                return nextIndex < data.endIndex && data[nextIndex] == lineFeed ? 2 : 1
            }
            return byte == lineFeed ? 1 : nil
        }
    }

    private static func utf16LittleEndianScalar(in data: Data, at index: Data.Index) -> UInt8? {
        guard index < data.endIndex else {
            return nil
        }
        let nextIndex = data.index(after: index)
        guard nextIndex < data.endIndex,
              data[nextIndex] == 0 else {
            return nil
        }
        return data[index]
    }

    private static func utf16BigEndianScalar(in data: Data, at index: Data.Index) -> UInt8? {
        guard index < data.endIndex else {
            return nil
        }
        let nextIndex = data.index(after: index)
        guard nextIndex < data.endIndex,
              data[index] == 0 else {
            return nil
        }
        return data[nextIndex]
    }

    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
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
