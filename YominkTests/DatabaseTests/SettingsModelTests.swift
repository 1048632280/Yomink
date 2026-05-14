import XCTest
@testable import Yomink

final class SettingsModelTests: XCTestCase {
    func testDefaultReadingSettingsUseCompactPerformanceSafeValues() {
        let settings = ReadingSettings.standard

        XCTAssertEqual(settings.theme, .paper)
        XCTAssertGreaterThan(settings.layout.fontSize, 0)
        XCTAssertGreaterThan(settings.layout.viewportSize.width, 0)
        XCTAssertGreaterThan(settings.layout.viewportSize.height, 0)
    }
}
