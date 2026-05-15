import XCTest
@testable import Yomink

final class ChapterParserTests: XCTestCase {
    func testParserFindsChapterHeadingsInsideBoundedWindow() throws {
        let text = [
            "\u{6B63}\u{6587}\u{5F00}\u{59CB}",
            "\u{7B2C}\u{4E00}\u{7AE0} \u{5F00}\u{59CB}",
            "\u{8FD9}\u{4E00}\u{884C}\u{53EA}\u{662F}\u{5185}\u{5BB9}",
            "Chapter 2 Return",
            "\u{5377}\u{4E09} \u{98CE}\u{8D77}"
        ].joined(separator: "\n")
        let data = Data(text.utf8)
        let byteRangeStart: UInt64 = 4_096

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: byteRangeStart..<(byteRangeStart + UInt64(data.count)),
            encoding: .utf8
        )

        XCTAssertEqual(
            candidates.map(\.title),
            [
                "\u{7B2C}\u{4E00}\u{7AE0} \u{5F00}\u{59CB}",
                "Chapter 2 Return",
                "\u{5377}\u{4E09} \u{98CE}\u{8D77}"
            ]
        )
        XCTAssertEqual(
            candidates.first?.byteOffset,
            byteRangeStart + UInt64("\u{6B63}\u{6587}\u{5F00}\u{59CB}\n".utf8.count)
        )
    }

    func testParserSkipsPartialFirstLineInContinuationWindow() throws {
        let text = [
            "\u{7B2C}\u{4E00}\u{7AE0} \u{5E94}\u{8BE5}\u{7531}\u{4E0A}\u{4E00}\u{7A97}\u{53E3}\u{8BC6}\u{522B}",
            "\u{7B2C}\u{4E8C}\u{7AE0} \u{65B0}\u{7A97}\u{53E3}"
        ].joined(separator: "\n")
        let data = Data(text.utf8)

        let candidates = try ChapterParser().parseCandidates(
            in: data,
            byteRange: 512..<(512 + UInt64(data.count)),
            encoding: .utf8
        )

        XCTAssertEqual(candidates.map(\.title), ["\u{7B2C}\u{4E8C}\u{7AE0} \u{65B0}\u{7A97}\u{53E3}"])
    }
}
