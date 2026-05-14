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
}
