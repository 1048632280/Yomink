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
}

struct CodableEdgeInsets: Hashable, Codable, Sendable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat
}
