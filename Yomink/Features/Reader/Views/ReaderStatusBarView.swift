import UIKit

final class ReaderStatusBarView: UIView {
    private let stackView = UIStackView()
    private var labels: [UILabel] = []
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
        chapterTitle: String?
    ) {
        let texts = ReadingStatusBarItem.allCases
            .filter { settings.statusBarItems.contains($0) }
            .compactMap { text(for: $0, state: state, chapterTitle: chapterTitle) }

        isHidden = texts.isEmpty
        rebuildLabels(texts)
    }

    func applyTheme(_ theme: ReadingTheme) {
        currentTheme = theme
        let palette = ReadingThemePalette.palette(for: theme)
        backgroundColor = palette.chromeBackground
        for label in labels {
            label.textColor = palette.secondaryText
        }
    }

    private func configureView() {
        isUserInteractionEnabled = false
        applyTheme(.paper)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 12

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func rebuildLabels(_ texts: [String]) {
        for label in labels {
            stackView.removeArrangedSubview(label)
            label.removeFromSuperview()
        }

        labels = texts.map { text in
            let label = UILabel()
            label.text = text
            label.font = .preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = ReadingThemePalette.palette(for: currentTheme).secondaryText
            label.lineBreakMode = .byTruncatingTail
            label.numberOfLines = 1
            stackView.addArrangedSubview(label)
            return label
        }
    }

    private func text(
        for item: ReadingStatusBarItem,
        state: ReaderSessionState,
        chapterTitle: String?
    ) -> String? {
        switch item {
        case .time:
            return Date().formatted(date: .omitted, time: .shortened)
        case .battery:
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
        case .batteryPercent:
            let level = UIDevice.current.batteryLevel
            guard level >= 0 else {
                return nil
            }
            return "\(Int((level * 100).rounded()))%"
        case .chapterTitle:
            return chapterTitle
        case .chapterPageProgress:
            return "\u{7B2C} \(state.currentPageIndex + 1) \u{9875}"
        case .bookProgress:
            return state.progressPercentText
        }
    }
}
