import CoreText
import UIKit

final class ReaderPageCell: UICollectionViewCell {
    static let reuseIdentifier = "ReaderPageCell"

    private let pageView = CoreTextPageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = YominkTheme.background
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pageView.configure(text: "", layout: .defaultPhone)
    }

    func configure(page: ReaderPage, layout: ReadingLayout) {
        pageView.configure(text: page.text, layout: layout)
    }
}

private final class CoreTextPageView: UIView {
    private var text = ""
    private var layout = ReadingLayout.defaultPhone

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = YominkTheme.background
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(text: String, layout: ReadingLayout) {
        self.text = text
        self.layout = layout
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !text.isEmpty,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let font = CTFontCreateWithName(layout.fontName as CFString, layout.fontSize, nil)
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): YominkTheme.primaryText.cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): makeParagraphStyle()
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(textRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private var textRect: CGRect {
        CGRect(
            x: layout.contentInsets.left,
            y: layout.contentInsets.bottom,
            width: max(1, bounds.width - layout.contentInsets.left - layout.contentInsets.right),
            height: max(1, bounds.height - layout.contentInsets.top - layout.contentInsets.bottom)
        )
    }

    private func makeParagraphStyle() -> CTParagraphStyle {
        var lineSpacing = layout.lineSpacing
        var paragraphSpacing = layout.paragraphSpacing
        return withUnsafePointer(to: &lineSpacing) { lineSpacingPointer in
            withUnsafePointer(to: &paragraphSpacing) { paragraphSpacingPointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(lineSpacingPointer)
                    ),
                    CTParagraphStyleSetting(
                        spec: .paragraphSpacing,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(paragraphSpacingPointer)
                    )
                ]
                return settings.withUnsafeBufferPointer { buffer in
                    CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
                }
            }
        }
    }
}

