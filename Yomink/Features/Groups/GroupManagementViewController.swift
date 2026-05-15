import UIKit

final class GroupManagementViewController: UIViewController {
    private enum Section {
        case main
    }

    var onCreateGroup: ((String) -> Void)?
    var onRenameGroup: ((UUID, String) -> Void)?
    var onDeleteGroup: ((UUID) -> Void)?

    private var groups: [BookGroupSummary]
    private var dataSource: UICollectionViewDiffableDataSource<Section, BookGroupSummary>?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = YominkTheme.background
            configuration.showsSeparators = true
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = YominkTheme.background
        return collectionView
    }()

    init(groups: [BookGroupSummary]) {
        self.groups = groups
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{7BA1}\u{7406}\u{5206}\u{7EC4}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    func update(groups: [BookGroupSummary]) {
        self.groups = groups
        applySnapshot()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addGroup)
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
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, BookGroupSummary> { cell, _, summary in
            var content = UIListContentConfiguration.valueCell()
            content.text = summary.group.name
            content.secondaryText = "\(summary.bookCount)"
            content.image = UIImage(systemName: "folder")
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText
            cell.accessories = [.disclosureIndicator()]
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, BookGroupSummary>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, BookGroupSummary>()
        snapshot.appendSections([.main])
        snapshot.appendItems(groups, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: true)
    }

    @objc private func addGroup() {
        presentNameAlert(title: "\u{65B0}\u{5EFA}\u{5206}\u{7EC4}", name: "") { [weak self] name in
            self?.onCreateGroup?(name)
        }
    }

    private func presentActions(for summary: BookGroupSummary) {
        let alert = UIAlertController(title: summary.group.name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(
            UIAlertAction(title: "\u{91CD}\u{547D}\u{540D}", style: .default) { [weak self] _ in
                self?.presentNameAlert(title: "\u{91CD}\u{547D}\u{540D}", name: summary.group.name) { name in
                    self?.onRenameGroup?(summary.group.id, name)
                }
            }
        )
        alert.addAction(
            UIAlertAction(title: "\u{5220}\u{9664}\u{5206}\u{7EC4}", style: .destructive) { [weak self] _ in
                self?.onDeleteGroup?(summary.group.id)
            }
        )
        alert.addAction(UIAlertAction(title: "\u{53D6}\u{6D88}", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func presentNameAlert(title: String, name: String, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = name
            textField.placeholder = "\u{5206}\u{7EC4}\u{540D}\u{79F0}"
        }
        alert.addAction(UIAlertAction(title: "\u{53D6}\u{6D88}", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "\u{786E}\u{5B9A}", style: .default) { _ in
                completion(alert.textFields?.first?.text ?? "")
            }
        )
        present(alert, animated: true)
    }
}

extension GroupManagementViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let summary = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }
        presentActions(for: summary)
    }
}
