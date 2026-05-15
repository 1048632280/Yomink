import UIKit

final class AppSettingsViewController: UIViewController {
    var onSettingsChanged: (() -> Void)?

    private let appSettingsStore: AppSettingsStore
    private let sortControl = UISegmentedControl(items: BookshelfSortMode.allCases.map(\.title))
    private let displayModeControl = UISegmentedControl(items: BookshelfDisplayMode.allCases.map(\.title))

    init(appSettingsStore: AppSettingsStore) {
        self.appSettingsStore = appSettingsStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{5E94}\u{7528}\u{8BBE}\u{7F6E}"
        view.backgroundColor = YominkTheme.background
        configureLayout()
        refreshControls()
    }

    private func configureLayout() {
        sortControl.addTarget(self, action: #selector(sortModeChanged), for: .valueChanged)
        displayModeControl.addTarget(self, action: #selector(displayModeChanged), for: .valueChanged)

        let sortTitleLabel = makeSectionTitleLabel(text: "\u{4E66}\u{67B6}\u{6392}\u{5E8F}")
        let displayTitleLabel = makeSectionTitleLabel(text: "\u{4E66}\u{67B6}\u{5C55}\u{793A}")

        let stackView = UIStackView(arrangedSubviews: [
            sortTitleLabel,
            sortControl,
            displayTitleLabel,
            displayModeControl
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func makeSectionTitleLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = YominkTheme.primaryText
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func refreshControls() {
        sortControl.selectedSegmentIndex = BookshelfSortMode.allCases.firstIndex(of: appSettingsStore.bookshelfSortMode) ?? 0
        displayModeControl.selectedSegmentIndex = BookshelfDisplayMode.allCases.firstIndex(of: appSettingsStore.bookshelfDisplayMode) ?? 0
    }

    @objc private func sortModeChanged() {
        let index = max(0, sortControl.selectedSegmentIndex)
        appSettingsStore.bookshelfSortMode = BookshelfSortMode.allCases[index]
        onSettingsChanged?()
    }

    @objc private func displayModeChanged() {
        let index = max(0, displayModeControl.selectedSegmentIndex)
        appSettingsStore.bookshelfDisplayMode = BookshelfDisplayMode.allCases[index]
        onSettingsChanged?()
    }
}
