import UIKit

final class ReaderStatusBarView: UIView {
    private let pageLabel = UILabel()
    private let progressLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(state: ReaderSessionState) {
        pageLabel.text = "\u{7B2C} \(state.currentPageIndex + 1) \u{9875}"
        if state.isLoadingNextPage {
            progressLabel.text = "\(state.progressPercentText) / \u{52A0}\u{8F7D}\u{4E2D}"
        } else if state.didReachEndOfBook {
            progressLabel.text = "\(state.progressPercentText) / \u{4E66}\u{672B}"
        } else {
            progressLabel.text = state.progressPercentText
        }
    }

    func applyTheme(_ theme: ReadingTheme) {
        let palette = ReadingThemePalette.palette(for: theme)
        backgroundColor = palette.chromeBackground
        pageLabel.textColor = palette.secondaryText
        progressLabel.textColor = palette.secondaryText
    }

    private func configureView() {
        isUserInteractionEnabled = false
        applyTheme(.paper)

        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        pageLabel.adjustsFontForContentSizeCategory = true

        progressLabel.font = .preferredFont(forTextStyle: .caption1)
        progressLabel.textAlignment = .right
        progressLabel.adjustsFontForContentSizeCategory = true

        let stackView = UIStackView(arrangedSubviews: [pageLabel, progressLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        stackView.spacing = 12

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
