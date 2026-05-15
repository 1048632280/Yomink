import UIKit

final class TapAreaSettingsViewController: UIViewController {
    var onApply: ((TapAreaSettings) -> Void)?

    private var settings: TapAreaSettings
    private var buttons: [UIButton] = []
    private let gridStack = UIStackView()

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
        configureGrid()
        refreshButtons()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "\u{5E94}\u{7528}",
            style: .done,
            target: self,
            action: #selector(apply)
        )
    }

    private func configureGrid() {
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        gridStack.axis = .vertical
        gridStack.spacing = 8
        view.addSubview(gridStack)

        for row in 0..<3 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 8
            gridStack.addArrangedSubview(rowStack)

            for column in 0..<3 {
                let index = row * 3 + column
                let button = UIButton(type: .system)
                button.tag = index
                button.titleLabel?.font = .preferredFont(forTextStyle: .body)
                button.titleLabel?.numberOfLines = 2
                button.backgroundColor = .secondarySystemBackground
                button.layer.cornerRadius = 8
                button.addTarget(self, action: #selector(areaTapped(_:)), for: .touchUpInside)
                buttons.append(button)
                rowStack.addArrangedSubview(button)
                button.heightAnchor.constraint(equalTo: button.widthAnchor).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            gridStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            gridStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
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
    }

    @objc private func apply() {
        onApply?(settings)
        dismiss(animated: true)
    }
}
