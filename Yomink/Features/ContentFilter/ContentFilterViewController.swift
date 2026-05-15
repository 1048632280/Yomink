import UIKit

final class ContentFilterViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Item: Hashable {
        case empty
        case rule(ContentFilterRule)
    }

    var onRulesChanged: (([ContentFilterRule]) -> Void)?

    private let bookID: UUID
    private let service: ContentFilterService
    private var rules: [ContentFilterRule]
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.backgroundColor = YominkTheme.background
            configuration.showsSeparators = true
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = YominkTheme.background
        return collectionView
    }()

    init(bookID: UUID, service: ContentFilterService, rules: [ContentFilterRule]) {
        self.bookID = bookID
        self.service = service
        self.rules = rules
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{5185}\u{5BB9}\u{51C0}\u{5316}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addRule)
        )
    }

    private func configureCollectionView() {
        view.addSubview(collectionView)
        collectionView.delegate = self
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = UIListContentConfiguration.valueCell()
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText

            switch item {
            case .empty:
                content.text = "\u{6682}\u{65E0}\u{8FC7}\u{6EE4}\u{89C4}\u{5219}"
                content.secondaryText = nil
                content.image = UIImage(systemName: "line.3.horizontal.decrease.circle")
            case .rule(let rule):
                content.text = rule.sourceText
                content.secondaryText = rule.replacementText ?? "\u{5220}\u{9664}"
                content.image = UIImage(systemName: "text.badge.minus")
            }

            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(rules.isEmpty ? [.empty] : rules.map(Item.rule), toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: true)
    }

    @objc private func addRule() {
        let alert = UIAlertController(title: "\u{6DFB}\u{52A0}\u{8FC7}\u{6EE4}", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "\u{8981}\u{8FC7}\u{6EE4}\u{7684}\u{5185}\u{5BB9}"
        }
        alert.addTextField { textField in
            textField.placeholder = "\u{66FF}\u{6362}\u{4E3A}\u{7684}\u{5185}\u{5BB9}"
        }
        alert.addAction(UIAlertAction(title: "\u{53D6}\u{6D88}", style: .cancel))
        alert.addAction(UIAlertAction(title: "\u{786E}\u{5B9A}", style: .default) { [weak self, weak alert] _ in
            let sourceText = alert?.textFields?.first?.text ?? ""
            let replacementText = alert?.textFields?[safe: 1]?.text
            self?.persistRule(sourceText: sourceText, replacementText: replacementText)
        })
        present(alert, animated: true)
    }

    private func persistRule(sourceText: String, replacementText: String?) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let rule = try await service.addRule(
                    bookID: bookID,
                    sourceText: sourceText,
                    replacementText: replacementText
                )
                if !rule.sourceText.isEmpty {
                    rules.append(rule)
                    onRulesChanged?(rules)
                    applySnapshot()
                }
            } catch {
                showError()
            }
        }
    }

    private func deleteRule(_ rule: ContentFilterRule, completion: @escaping (Bool) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else {
                completion(false)
                return
            }
            do {
                try await service.deleteRule(rule)
                rules.removeAll { $0.id == rule.id }
                onRulesChanged?(rules)
                applySnapshot()
                completion(true)
            } catch {
                showError()
                completion(false)
            }
        }
    }

    private func showError() {
        let alert = UIAlertController(title: "\u{8FC7}\u{6EE4}\u{89C4}\u{5219}\u{4FDD}\u{5B58}\u{5931}\u{8D25}", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        present(alert, animated: true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ContentFilterViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .rule(let rule) = item else {
            return nil
        }

        let deleteAction = UIContextualAction(style: .destructive, title: "\u{5220}\u{9664}") { [weak self] _, _, completion in
            self?.deleteRule(rule, completion: completion)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
