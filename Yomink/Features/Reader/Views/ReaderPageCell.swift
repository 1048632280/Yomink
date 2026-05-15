import CoreText
import UIKit

final class ReaderPageCell: UICollectionViewCell {
    static let reuseIdentifier = "ReaderPageCell"

    private let pageView = CoreTextPageView()
    private let statusBarView = ReaderStatusBarView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = YominkTheme.background
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageView)
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.isHidden = true
        contentView.addSubview(statusBarView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            statusBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
            statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pageView.configure(text: "", settings: .standard)
        statusBarView.isHidden = true
    }

    func configure(
        page: ReaderPage,
        settings: ReadingSettings,
        filterRules: [ContentFilterRule] = [],
        statusConfiguration: ReaderStatusBarView.Configuration? = nil
    ) {
        let palette = ReadingThemePalette.palette(for: settings.theme)
        contentView.backgroundColor = palette.background
        let displayText = page.text.applyingContentFilters(filterRules)
        pageView.configure(text: displayText, settings: settings)
        statusBarView.applyTheme(settings.theme)
        if let statusConfiguration {
            statusBarView.configure(statusConfiguration)
        } else {
            statusBarView.isHidden = true
        }
    }
}

private extension String {
    func applyingContentFilters(_ rules: [ContentFilterRule]) -> String {
        guard !rules.isEmpty, !isEmpty else {
            return self
        }

        var filteredText = self
        for rule in rules where !rule.sourceText.isEmpty {
            filteredText = filteredText.replacingOccurrences(
                of: rule.sourceText,
                with: rule.replacementText ?? "",
                options: [.caseInsensitive]
            )
        }
        return filteredText
    }
}

private final class CoreTextPageView: UIView {
    private var text = ""
    private var settings = ReadingSettings.standard

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

    func configure(text: String, settings: ReadingSettings) {
        self.text = text
        self.settings = settings
        backgroundColor = ReadingThemePalette.palette(for: settings.theme).background
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

        let layout = settings.layout
        let palette = ReadingThemePalette.palette(for: settings.theme)
        let attributedString = ReaderTextStyler.attributedText(
            for: text,
            layout: layout,
            foregroundColor: palette.primaryText.cgColor
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        path.addRect(settings.layout.contentRect(in: bounds))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

}
