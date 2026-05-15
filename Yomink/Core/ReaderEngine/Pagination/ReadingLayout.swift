import CoreGraphics
import Foundation

struct ReadingLayout: Hashable, Codable, Sendable {
    var viewportSize: CGSize
    var contentInsets: CodableEdgeInsets
    var fontName: String
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat

    static let defaultPhone = ReadingLayout(
        viewportSize: CGSize(width: 390, height: 844),
        contentInsets: CodableEdgeInsets(top: 28, left: 24, bottom: 28, right: 24),
        fontName: "PingFangSC-Regular",
        fontSize: 18,
        lineSpacing: 6,
        paragraphSpacing: 10
    )

    func contentRect(in bounds: CGRect) -> CGRect {
        // CoreText pagination and drawing both use the flipped bottom-left coordinate space.
        CGRect(
            x: contentInsets.left,
            y: contentInsets.bottom,
            width: max(1, bounds.width - contentInsets.left - contentInsets.right),
            height: max(1, bounds.height - contentInsets.top - contentInsets.bottom)
        )
    }
}

struct CodableEdgeInsets: Hashable, Codable, Sendable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat
}
