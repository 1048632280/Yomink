import UIKit

final class ReaderStatusBarView: UIView {
    struct ChapterProgress: Hashable {
        let pageIndex: Int
        let pageCount: Int?

        var displayText: String {
            if let pageCount {
                return "\u{672C}\u{7AE0} \(pageIndex + 1)/\(pageCount) \u{9875}"
            }
            return "\u{672C}\u{7AE0}\u{7B2C} \(pageIndex + 1) \u{9875}"
        }
    }

    private let topLeftLabel = UILabel()
    private let bottomLeftStackView = UIStackView()
    private let bottomRightStackView = UIStackView()
    private var currentTheme: ReadingTheme = .paper

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
        let visibleItems = settings.statusBarItems
        topLeftLabel.text = visibleItems.contains(.chapterTitle) ? chapterTitle : nil

        let bottomLeftTexts: [String?] = [
            visibleItems.contains(.batteryPercent) ? batteryPercentText() : nil,
            visibleItems.contains(.battery) ? batteryStateText() : nil,
            visibleItems.contains(.time) ? Date().formatted(date: .omitted, time: .shortened) : nil
        ]
        rebuildLabels(in: bottomLeftStackView, texts: bottomLeftTexts.compactMap { $0 })

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
        bottomLeftStackView.spacing = 8
        bottomLeftStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bottomRightStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomRightStackView.axis = .horizontal
        bottomRightStackView.alignment = .center
        bottomRightStackView.spacing = 8
        bottomRightStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(topLeftLabel)
        addSubview(bottomLeftStackView)
        addSubview(bottomRightStackView)

        NSLayoutConstraint.activate([
            topLeftLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            topLeftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            topLeftLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            bottomLeftStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            bottomLeftStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomLeftStackView.trailingAnchor.constraint(lessThanOrEqualTo: bottomRightStackView.leadingAnchor, constant: -12),
            bottomLeftStackView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.48),

            bottomRightStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            bottomRightStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomRightStackView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.48)
        ])

        applyTheme(.paper)
    }

    private func rebuildLabels(in stackView: UIStackView, texts: [String]) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for text in texts {
            let label = UILabel()
            label.text = text
            label.font = .preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
            label.numberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            applyTextColor(to: label)
            stackView.addArrangedSubview(label)
        }
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

    private func batteryStateText() -> String? {
        switch UIDevice.current.batteryState {
        case .charging, .full:
            return "\u{7535}\u{6C60}\u{5145}\u{7535}"
        case .unplugged:
            return "\u{7535}\u{6C60}"
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}
