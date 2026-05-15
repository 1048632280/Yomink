import UIKit

final class TapAreaSettingsViewController: UIViewController {
    var onChange: ((TapAreaSettings) -> Void)?

    private var settings: TapAreaSettings
    private var buttons: [UIButton] = []
    private let gridStack = UIStackView()
    private let sideSwipeHintLabel = UILabel()
    private let footerLabel = UILabel()

    init(settings: TapAreaSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{7FFB}\u{9875}\u{533A}\u{57DF}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureSideSwipeHint()
        configureGrid()
        configureFooter()
        refreshButtons()
    }

    private func configureNavigation() {
        guard navigationController?.viewControllers.first === self else {
            return
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
    }

    private func configureSideSwipeHint() {
        sideSwipeHintLabel.translatesAutoresizingMaskIntoConstraints = false
        sideSwipeHintLabel.text = "\u{4FA7}\u{6ED1}\n\u{8FD4}\u{56DE}\n\u{4E66}\u{67B6}"
        sideSwipeHintLabel.font = .preferredFont(forTextStyle: .caption2)
        sideSwipeHintLabel.adjustsFontForContentSizeCategory = true
        sideSwipeHintLabel.textColor = YominkTheme.secondaryText
        sideSwipeHintLabel.textAlignment = .center
        sideSwipeHintLabel.numberOfLines = 3
        view.addSubview(sideSwipeHintLabel)
    }

    private func configureGrid() {
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        gridStack.axis = .vertical
        gridStack.spacing = 10
        gridStack.distribution = .fillEqually
        view.addSubview(gridStack)

        for row in 0..<3 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 10
            gridStack.addArrangedSubview(rowStack)

            for column in 0..<3 {
                let index = row * 3 + column
                let button = UIButton(type: .system)
                button.tag = index
                button.titleLabel?.font = .preferredFont(forTextStyle: .body)
                button.titleLabel?.numberOfLines = 2
                button.backgroundColor = .secondarySystemBackground
                button.layer.cornerRadius = 8
                button.layer.borderWidth = 1
                button.layer.borderColor = UIColor.separator.cgColor
                button.addTarget(self, action: #selector(areaTapped(_:)), for: .touchUpInside)
                buttons.append(button)
                rowStack.addArrangedSubview(button)
            }
        }

        let preferredGridWidth = gridStack.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -72
        )
        preferredGridWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            sideSwipeHintLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            sideSwipeHintLabel.centerYAnchor.constraint(equalTo: gridStack.centerYAnchor),
            sideSwipeHintLabel.widthAnchor.constraint(equalToConstant: 28),

            gridStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -16),
            gridStack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor, constant: 14),
            gridStack.leadingAnchor.constraint(greaterThanOrEqualTo: sideSwipeHintLabel.trailingAnchor, constant: 8),
            gridStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            gridStack.heightAnchor.constraint(equalTo: gridStack.widthAnchor),
            gridStack.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, constant: -120),
            preferredGridWidth
        ])
    }

    private func configureFooter() {
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.text = "\u{70B9}\u{51FB}\u{4EFB}\u{610F}\u{533A}\u{57DF}\u{5373}\u{65F6}\u{5207}\u{6362}\u{64CD}\u{4F5C}"
        footerLabel.font = .preferredFont(forTextStyle: .footnote)
        footerLabel.adjustsFontForContentSizeCategory = true
        footerLabel.textColor = YominkTheme.secondaryText
        footerLabel.textAlignment = .center
        view.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            footerLabel.topAnchor.constraint(equalTo: gridStack.bottomAnchor, constant: 18),
            footerLabel.leadingAnchor.constraint(equalTo: gridStack.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: gridStack.trailingAnchor)
        ])
    }

    private func refreshButtons() {
        for button in buttons {
            button.setTitle(settings.action(for: button.tag).displayName, for: .normal)
        }
    }

    @objc private func areaTapped(_ sender: UIButton) {
        let currentAction = settings.action(for: sender.tag)
        let actions = ReaderTapAreaAction.allCases
        let nextIndex = ((actions.firstIndex(of: currentAction) ?? 0) + 1) % actions.count
        settings.setAction(actions[nextIndex], for: sender.tag)
        refreshButtons()
        onChange?(settings)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
