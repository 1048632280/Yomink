import UIKit

final class ReaderStatusBarView: UIView {
    struct Configuration: Hashable {
        let state: ReaderSessionState
        let settings: ReadingSettings
        let chapterTitle: String?
        let chapterProgress: ChapterProgress?
    }

    struct ChapterProgress: Hashable {
        let pageIndex: Int
        let pageCount: Int?

        var displayText: String? {
            if let pageCount {
                return "\(pageIndex + 1)/\(pageCount)"
            }
            return nil
        }
    }

    private let topLeftLabel = UILabel()
    private let bottomLeftStackView = UIStackView()
    private let bottomRightStackView = UIStackView()
    private let batteryIconView = BatteryIndicatorView()
    private var currentTheme: ReadingTheme = .paper
    private var topTitleTopConstraint: NSLayoutConstraint?
    private var topTitleLeadingConstraint: NSLayoutConstraint?
    private var topTitleTrailingConstraint: NSLayoutConstraint?
    private var bottomLeftLeadingConstraint: NSLayoutConstraint?
    private var bottomLeftBottomConstraint: NSLayoutConstraint?
    private var bottomRightTrailingConstraint: NSLayoutConstraint?
    private var bottomRightBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        state: ReaderSessionState,
        settings: ReadingSettings,
        chapterTitle: String?,
        chapterProgress: ChapterProgress?
    ) {
        configure(
            Configuration(
                state: state,
                settings: settings,
                chapterTitle: chapterTitle,
                chapterProgress: chapterProgress
            )
        )
    }

    func configure(_ configuration: Configuration) {
        let state = configuration.state
        let settings = configuration.settings
        let chapterTitle = configuration.chapterTitle
        let chapterProgress = configuration.chapterProgress
        let visibleItems = settings.statusBarItems
        applyWidgetLayout(settings.layout.widgetLayout)
        topLeftLabel.text = visibleItems.contains(.chapterTitle) ? chapterTitle : nil

        rebuildBottomLeftItems(visibleItems: visibleItems)

        let bottomRightTexts: [String?] = [
            visibleItems.contains(.chapterPageProgress) ? chapterProgress?.displayText : nil,
            visibleItems.contains(.bookProgress) ? state.progressPercentText : nil
        ]
        rebuildLabels(in: bottomRightStackView, texts: bottomRightTexts.compactMap { $0 })

        isHidden = topLeftLabel.text?.isEmpty != false
            && bottomLeftStackView.arrangedSubviews.isEmpty
            && bottomRightStackView.arrangedSubviews.isEmpty
    }

    func applyTheme(_ theme: ReadingTheme) {
        currentTheme = theme
        backgroundColor = .clear
        applyTextColor(to: topLeftLabel)
        topLeftLabel.textColor = .secondaryLabel
        batteryIconView.applyTheme(theme)
        for stackView in [bottomLeftStackView, bottomRightStackView] {
            for case let label as UILabel in stackView.arrangedSubviews {
                applyTextColor(to: label)
            }
        }
    }

    private func configureView() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        topLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        topLeftLabel.font = .preferredFont(forTextStyle: .caption1)
        topLeftLabel.adjustsFontForContentSizeCategory = true
        topLeftLabel.lineBreakMode = .byTruncatingTail
        topLeftLabel.numberOfLines = 1
        topLeftLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bottomLeftStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomLeftStackView.axis = .horizontal
        bottomLeftStackView.alignment = .center
        bottomLeftStackView.spacing = 5
        bottomLeftStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bottomRightStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomRightStackView.axis = .horizontal
        bottomRightStackView.alignment = .center
        bottomRightStackView.spacing = 8
        bottomRightStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(topLeftLabel)
        addSubview(bottomLeftStackView)
        addSubview(bottomRightStackView)

        topTitleTopConstraint = topLeftLabel.topAnchor.constraint(equalTo: topAnchor, constant: 43)
        topTitleLeadingConstraint = topLeftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        topTitleTrailingConstraint = topLeftLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        bottomLeftLeadingConstraint = bottomLeftStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        bottomLeftBottomConstraint = bottomLeftStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -27)
        bottomRightTrailingConstraint = bottomRightStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        bottomRightBottomConstraint = bottomRightStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -27)

        let constraints: [NSLayoutConstraint?] = [
            topTitleTopConstraint,
            topTitleLeadingConstraint,
            topTitleTrailingConstraint,
            bottomLeftLeadingConstraint,
            bottomLeftBottomConstraint,
            bottomLeftStackView.trailingAnchor.constraint(lessThanOrEqualTo: bottomRightStackView.leadingAnchor, constant: -12),
            bottomLeftStackView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, multiplier: 0.48),
            bottomRightTrailingConstraint,
            bottomRightBottomConstraint,
            bottomRightStackView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, multiplier: 0.48)
        ]
        NSLayoutConstraint.activate(constraints.compactMap { $0 })

        applyTheme(.paper)
    }

    private func applyWidgetLayout(_ layout: ReadingWidgetLayout) {
        topTitleTopConstraint?.constant = layout.titleTopInset
        topTitleLeadingConstraint?.constant = layout.titleLeftInset
        topTitleTrailingConstraint?.constant = -layout.rightInset
        bottomLeftLeadingConstraint?.constant = layout.leftInset
        bottomLeftBottomConstraint?.constant = -layout.bottomInset
        bottomRightTrailingConstraint?.constant = -layout.rightInset
        bottomRightBottomConstraint?.constant = -layout.bottomInset
    }

    private func rebuildBottomLeftItems(visibleItems: Set<ReadingStatusBarItem>) {
        removeArrangedSubviews(from: bottomLeftStackView)

        if visibleItems.contains(.batteryPercent),
           let batteryPercentText = batteryPercentText() {
            bottomLeftStackView.addArrangedSubview(makeLabel(text: batteryPercentText))
        }

        if visibleItems.contains(.battery) {
            batteryIconView.configure(level: UIDevice.current.batteryLevel, state: UIDevice.current.batteryState)
            bottomLeftStackView.addArrangedSubview(batteryIconView)
        }

        if visibleItems.contains(.time) {
            bottomLeftStackView.addArrangedSubview(
                makeLabel(text: Date().formatted(date: .omitted, time: .shortened))
            )
        }
    }

    private func rebuildLabels(in stackView: UIStackView, texts: [String]) {
        removeArrangedSubviews(from: stackView)
        appendLabels(to: stackView, texts: texts)
    }

    private func removeArrangedSubviews(from stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func appendLabels(to stackView: UIStackView, texts: [String]) {
        for text in texts {
            stackView.addArrangedSubview(makeLabel(text: text))
        }
    }

    private func makeLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyTextColor(to: label)
        return label
    }

    private func applyTextColor(to label: UILabel) {
        label.textColor = ReadingThemePalette.palette(for: currentTheme).secondaryText
    }

    private func batteryPercentText() -> String? {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else {
            return nil
        }
        return "\(Int((level * 100).rounded()))%"
    }
}

private final class BatteryIndicatorView: UIView {
    private let bodyLayer = CAShapeLayer()
    private let capLayer = CAShapeLayer()
    private let fillLayer = CALayer()
    private var level: Float = 0
    private var batteryState: UIDevice.BatteryState = .unknown
    private var currentTheme: ReadingTheme = .paper

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isOpaque = false
        layer.addSublayer(fillLayer)
        layer.addSublayer(bodyLayer)
        layer.addSublayer(capLayer)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(level: Float, state: UIDevice.BatteryState) {
        self.level = max(0, min(1, level))
        batteryState = state
        setNeedsLayout()
    }

    func applyTheme(_ theme: ReadingTheme) {
        currentTheme = theme
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let strokeColor = ReadingThemePalette.palette(for: currentTheme).secondaryText.cgColor
        let bodyRect = CGRect(x: 0, y: 1, width: max(1, bounds.width - 3), height: max(1, bounds.height - 2))
        let capRect = CGRect(x: bodyRect.maxX + 1, y: bounds.midY - 2, width: 2, height: 4)
        bodyLayer.path = UIBezierPath(roundedRect: bodyRect, cornerRadius: 2).cgPath
        bodyLayer.fillColor = UIColor.clear.cgColor
        bodyLayer.strokeColor = strokeColor
        bodyLayer.lineWidth = 1

        capLayer.path = UIBezierPath(roundedRect: capRect, cornerRadius: 1).cgPath
        capLayer.fillColor = strokeColor
        capLayer.strokeColor = nil

        let fillInset: CGFloat = 2
        let fillWidth = max(0, (bodyRect.width - fillInset * 2) * CGFloat(level))
        fillLayer.frame = CGRect(
            x: bodyRect.minX + fillInset,
            y: bodyRect.minY + fillInset,
            width: fillWidth,
            height: max(0, bodyRect.height - fillInset * 2)
        )
        fillLayer.cornerRadius = 1
        fillLayer.backgroundColor = fillColor().cgColor
    }

    private func fillColor() -> UIColor {
        switch batteryState {
        case .charging, .full:
            return .systemGreen
        case .unplugged:
            return ReadingThemePalette.palette(for: currentTheme).secondaryText
        case .unknown:
            return ReadingThemePalette.palette(for: currentTheme).secondaryText.withAlphaComponent(0.35)
        @unknown default:
            return ReadingThemePalette.palette(for: currentTheme).secondaryText.withAlphaComponent(0.35)
        }
    }
}
