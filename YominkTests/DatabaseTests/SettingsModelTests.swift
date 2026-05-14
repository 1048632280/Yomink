import CoreGraphics
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

    func testReadingSettingsNormalizationClampsLayoutRanges() {
        var settings = ReadingSettings.standard
        settings.layout.fontSize = 200
        settings.layout.lineSpacing = -20
        settings.layout.paragraphSpacing = 100

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.layout.fontSize, CGFloat(ReadingSettings.fontSizeRange.upperBound))
        XCTAssertEqual(normalized.layout.lineSpacing, CGFloat(ReadingSettings.lineSpacingRange.lowerBound))
        XCTAssertEqual(
            normalized.layout.paragraphSpacing,
            CGFloat(ReadingSettings.paragraphSpacingRange.upperBound)
        )
    }

    func testReadingSettingsStoreSavesNormalizedValues() {
        let suiteName = "YominkTests.ReadingSettings.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        var settings = ReadingSettings.standard
        settings.theme = .black
        settings.layout.fontSize = 2

        let store = ReadingSettingsStore(userDefaults: userDefaults)
        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded.theme, .black)
        XCTAssertEqual(loaded.layout.fontSize, CGFloat(ReadingSettings.fontSizeRange.lowerBound))
    }
}
