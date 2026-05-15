import Foundation

enum ChapterParserError: Error {
    case undecodableWindow
}

struct ChapterCandidate: Hashable, Codable, Sendable {
    let title: String
    let byteOffset: UInt64
}

final class ChapterParser: @unchecked Sendable {
    static let maximumWindowLength: UInt64 = 256 * 1024
    static let overlapLength: UInt64 = 512

    func parseCandidates(
        in data: Data,
        byteRange: Range<UInt64>,
        encoding: TextEncoding
    ) throws -> [ChapterCandidate] {
        guard !data.isEmpty else {
            return []
        }

        let decodedWindow = try decodeWindow(data: data, encoding: encoding)
        let windowStartByteOffset = byteRange.lowerBound + decodedWindow.trimmedPrefixByteCount
        var consumedByteCount: UInt64 = 0
        var candidates: [ChapterCandidate] = []
        var isFirstLine = true

        // Chapter parsing walks only the bounded mmap window currently in memory.
        decodedWindow.text.enumerateSubstrings(
            in: decodedWindow.text.startIndex..<decodedWindow.text.endIndex,
            options: .byLines
        ) { substring, _, enclosingRange, _ in
            defer {
                isFirstLine = false
                let consumedLine = String(decodedWindow.text[enclosingRange])
                consumedByteCount += UInt64(Self.encodedByteCount(consumedLine, encoding: encoding))
            }

            guard !(byteRange.lowerBound > 0 && isFirstLine),
                  let substring,
                  let title = Self.normalizedChapterTitle(from: substring) else {
                return
            }

            candidates.append(
                ChapterCandidate(
                    title: title,
                    byteOffset: windowStartByteOffset + consumedByteCount
                )
            )
        }

        return candidates
    }

    private func decodeWindow(data: Data, encoding: TextEncoding) throws -> DecodedWindow {
        if let text = String(data: data, encoding: encoding.stringEncoding) {
            return DecodedWindow(text: text, trimmedPrefixByteCount: 0)
        }

        let maximumTrimLength = min(4, data.count)
        for prefixLength in 0...maximumTrimLength {
            for suffixLength in 0...maximumTrimLength {
                guard prefixLength + suffixLength < data.count else {
                    continue
                }

                let lowerBound = data.startIndex + prefixLength
                let upperBound = data.endIndex - suffixLength
                let trimmedData = Data(data[lowerBound..<upperBound])
                if let text = String(data: trimmedData, encoding: encoding.stringEncoding) {
                    return DecodedWindow(
                        text: text,
                        trimmedPrefixByteCount: UInt64(prefixLength)
                    )
                }
            }
        }

        throw ChapterParserError.undecodableWindow
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

    private static func encodedByteCount(_ text: String, encoding: TextEncoding) -> Int {
        text.data(using: encoding.stringEncoding)?.count ?? text.utf8.count
    }
}

private struct DecodedWindow {
    let text: String
    let trimmedPrefixByteCount: UInt64
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
