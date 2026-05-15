import UIKit

final class ReaderChromeView: UIView {
    enum Action {
        case back
        case bookmark
        case more
        case previousChapter
        case nextChapter
        case catalog
        case settings
        case autoRead
    }

    var onAction: ((Action) -> Void)?
    var onBackgroundTap: (() -> Void)?
    var onProgressPreview: ((Float) -> String)?
    var onProgressCommit: ((Float) -> Void)?

    private let topBar = UIView()
    private let bottomBar = UIView()
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressSlider = UISlider()
    private var isDraggingProgress = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        configureTopBar()
        configureBottomBar()
        setVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, state: ReaderSessionState?, theme: ReadingTheme) {
        titleLabel.text = title
        applyTheme(theme)

        guard let state else {
            progressLabel.text = "0.00%"
            progressSlider.value = 0
            return
        }

        if !isDraggingProgress {
            progressLabel.text = state.progressPercentText
            progressSlider.value = Float(Double(state.startByteOffset) / Double(max(1, state.fileSize)))
        }
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        let updates = {
            self.alpha = isVisible ? 1 : 0
        }

        isHidden = false
        isUserInteractionEnabled = isVisible
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                updates()
            } completion: { _ in
                self.isHidden = !isVisible
            }
        } else {
            updates()
            isHidden = !isVisible
        }
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }

    private func configureTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)

        let backButton = makeIconButton(systemName: "chevron.left", action: #selector(backTapped))
        let bookmarkButton = makeIconButton(systemName: "bookmark", action: #selector(bookmarkTapped))
        let moreButton = makeIconButton(systemName: "ellipsis", action: #selector(moreTapped))

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let stackView = UIStackView(arrangedSubviews: [backButton, titleLabel, bookmarkButton, moreButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        topBar.addSubview(stackView)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),

            stackView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),

            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 44),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 44),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)

        let previousButton = makeIconButton(systemName: "chevron.up", action: #selector(previousChapterTapped))
        let nextButton = makeIconButton(systemName: "chevron.down", action: #selector(nextChapterTapped))
        progressSlider.addTarget(self, action: #selector(progressEditingBegan), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(progressValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(progressEditingEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        progressLabel.font = .preferredFont(forTextStyle: .caption1)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textAlignment = .center

        let progressStack = UIStackView(arrangedSubviews: [previousButton, progressSlider, nextButton])
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressStack.axis = .horizontal
        progressStack.alignment = .center
        progressStack.spacing = 12

        let autoReadButton = makeLabeledButton(title: "\u{81EA}\u{52A8}", systemName: "play.circle", action: #selector(autoReadTapped))
        let catalogButton = makeLabeledButton(title: "\u{76EE}\u{5F55}", systemName: "list.bullet", action: #selector(catalogTapped))
        let settingsButton = makeLabeledButton(title: "\u{8BBE}\u{7F6E}", systemName: "textformat.size", action: #selector(settingsTapped))
        let actionStack = UIStackView(arrangedSubviews: [autoReadButton, catalogButton, settingsButton])
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.distribution = .fillEqually
        actionStack.spacing = 16

        let stackView = UIStackView(arrangedSubviews: [progressStack, progressLabel, actionStack])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 10
        bottomBar.addSubview(stackView)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),

            previousButton.widthAnchor.constraint(equalToConstant: 44),
            previousButton.heightAnchor.constraint(equalToConstant: 44),
            nextButton.widthAnchor.constraint(equalToConstant: 44),
            nextButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func makeIconButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeLabeledButton(title: String, systemName: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.title = title

        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func applyTheme(_ theme: ReadingTheme) {
        let palette = ReadingThemePalette.palette(for: theme)
        topBar.backgroundColor = palette.chromeBackground
        bottomBar.backgroundColor = palette.chromeBackground
        titleLabel.textColor = palette.primaryText
        progressLabel.textColor = palette.secondaryText
        progressSlider.tintColor = palette.primaryText
        tintColor = palette.primaryText
    }

    @objc private func progressEditingBegan() {
        isDraggingProgress = true
        progressValueChanged()
    }

    @objc private func progressValueChanged() {
        progressLabel.text = onProgressPreview?(progressSlider.value)
    }

    @objc private func progressEditingEnded() {
        isDraggingProgress = false
        onProgressCommit?(progressSlider.value)
    }

    @objc private func backTapped() {
        onAction?(.back)
    }

    @objc private func bookmarkTapped() {
        onAction?(.bookmark)
    }

    @objc private func moreTapped() {
        onAction?(.more)
    }

    @objc private func previousChapterTapped() {
        onAction?(.previousChapter)
    }

    @objc private func nextChapterTapped() {
        onAction?(.nextChapter)
    }

    @objc private func catalogTapped() {
        onAction?(.catalog)
    }

    @objc private func settingsTapped() {
        onAction?(.settings)
    }

    @objc private func autoReadTapped() {
        onAction?(.autoRead)
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        let location = gesture.location(in: self)
        guard !topBar.frame.contains(location),
              !bottomBar.frame.contains(location) else {
            return
        }
        onBackgroundTap?()
    }
}
