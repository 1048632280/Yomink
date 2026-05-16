import UIKit

@MainActor
struct ReadingThemePalette {
    let background: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let chromeBackground: UIColor

    static func palette(for theme: ReadingTheme) -> ReadingThemePalette {
        switch theme {
        case .paper:
            return ReadingThemePalette(
                background: ReadingPaperTexture.backgroundColor(),
                primaryText: UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1),
                secondaryText: UIColor(red: 0.42, green: 0.43, blue: 0.44, alpha: 1),
                chromeBackground: UIColor(red: 0.968, green: 0.967, blue: 0.952, alpha: 0.88)
            )
        case .white:
            return ReadingThemePalette(
                background: UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1),
                primaryText: UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1),
                secondaryText: UIColor(red: 0.38, green: 0.39, blue: 0.40, alpha: 1),
                chromeBackground: UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 0.88)
            )
        case .eyeCare:
            return ReadingThemePalette(
                background: UIColor(red: 0.90, green: 0.95, blue: 0.88, alpha: 1),
                primaryText: UIColor(red: 0.09, green: 0.13, blue: 0.10, alpha: 1),
                secondaryText: UIColor(red: 0.36, green: 0.44, blue: 0.36, alpha: 1),
                chromeBackground: UIColor(red: 0.90, green: 0.95, blue: 0.88, alpha: 0.88)
            )
        case .black:
            return ReadingThemePalette(
                background: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1),
                primaryText: UIColor(red: 0.78, green: 0.78, blue: 0.74, alpha: 1),
                secondaryText: UIColor(red: 0.48, green: 0.48, blue: 0.46, alpha: 1),
                chromeBackground: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.90)
            )
        }
    }
}
