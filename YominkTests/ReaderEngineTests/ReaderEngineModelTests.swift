import CoreText
import XCTest
@testable import Yomink

final class ReaderEngineModelTests: XCTestCase {
    func testTextWindowKeepsByteOffsets() {
        let window = TextWindow(byteRange: 128..<256, text: "Yomink")

        XCTAssertEqual(window.startByteOffset, 128)
        XCTAssertEqual(window.endByteOffset, 256)
        XCTAssertEqual(window.text, "Yomink")
    }

    func testPageByteRangeKeepsProgressCoordinates() {
        let bookID = UUID()
        let page = PageByteRange(bookID: bookID, pageIndex: 3, byteRange: 512..<1024)

        XCTAssertEqual(page.bookID, bookID)
        XCTAssertEqual(page.pageIndex, 3)
        XCTAssertEqual(page.startByteOffset, 512)
        XCTAssertEqual(page.endByteOffset, 1024)
    }

    func testReaderEngineWindowLimitsAreBounded() {
        XCTAssertLessThanOrEqual(BookFileMapping.maximumWindowLength, 1 * 1024 * 1024)
        XCTAssertLessThanOrEqual(CoreTextPaginator.maximumUTF16Length, 120_000)
    }

    func testReaderSessionStateUsesByteOffsetProgress() {
        let bookID = UUID()
        let state = ReaderSessionState(
            bookID: bookID,
            currentPageIndex: 4,
            residentPageCount: 3,
            startByteOffset: 512,
            endByteOffset: 768,
            fileSize: 1_024,
            isLoadingNextPage: false,
            didReachEndOfBook: false
        )

        XCTAssertEqual(state.bookID, bookID)
        XCTAssertEqual(state.progressFraction, 0.5)
        XCTAssertEqual(state.progressPercentText, "50.0%")
    }

    func testReaderSessionStateClampsInvalidProgressInputs() {
        let emptyState = ReaderSessionState(
            bookID: UUID(),
            currentPageIndex: 0,
            residentPageCount: 1,
            startByteOffset: 256,
            endByteOffset: 512,
            fileSize: 0,
            isLoadingNextPage: false,
            didReachEndOfBook: false
        )
        let oversizedState = ReaderSessionState(
            bookID: UUID(),
            currentPageIndex: 0,
            residentPageCount: 1,
            startByteOffset: 2_048,
            endByteOffset: 2_304,
            fileSize: 1_024,
            isLoadingNextPage: false,
            didReachEndOfBook: true
        )

        XCTAssertEqual(emptyState.progressFraction, 0)
        XCTAssertEqual(oversizedState.progressFraction, 1)
    }

    func testReaderTextStylerDoesNotStackSyntheticIndentOnSourceIndent() throws {
        var layout = ReadingLayout.defaultPhone
        layout.fontSize = 18
        layout.firstLineIndent = 2
        let text = "　　已有缩进\n没有缩进"
        let attributedText = ReaderTextStyler.attributedText(for: text, layout: layout)

        let firstParagraphStyle = try XCTUnwrap(paragraphStyle(in: attributedText, at: 0))
        let secondParagraphLocation = (text as NSString).range(of: "没有缩进").location
        let secondParagraphStyle = try XCTUnwrap(paragraphStyle(in: attributedText, at: secondParagraphLocation))

        XCTAssertEqual(firstLineHeadIndent(in: firstParagraphStyle), 0)
        XCTAssertEqual(firstLineHeadIndent(in: secondParagraphStyle), 36)
        XCTAssertEqual(alignment(in: secondParagraphStyle), .justified)
    }

    private func paragraphStyle(in attributedText: NSAttributedString, at location: Int) -> CTParagraphStyle? {
        attributedText.attribute(
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String),
            at: location,
            effectiveRange: nil
        ) as? CTParagraphStyle
    }

    private func firstLineHeadIndent(in paragraphStyle: CTParagraphStyle) -> CGFloat {
        var value: CGFloat = 0
        CTParagraphStyleGetValueForSpecifier(
            paragraphStyle,
            .firstLineHeadIndent,
            MemoryLayout<CGFloat>.size,
            &value
        )
        return value
    }

    private func alignment(in paragraphStyle: CTParagraphStyle) -> CTTextAlignment {
        var value = CTTextAlignment.natural
        CTParagraphStyleGetValueForSpecifier(
            paragraphStyle,
            .alignment,
            MemoryLayout<CTTextAlignment>.size,
            &value
        )
        return value
    }
}
