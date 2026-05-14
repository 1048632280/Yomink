import Foundation

struct ChapterCandidate: Hashable, Codable {
    let title: String
    let byteOffset: UInt64
}

final class ChapterParser {
    func scheduleIncrementalParsing(bookID: UUID, from startByteOffset: UInt64) {
        // Future work: parse chapter candidates in bounded byte windows, never by whole-file regex.
        _ = (bookID, startByteOffset)
    }
}
