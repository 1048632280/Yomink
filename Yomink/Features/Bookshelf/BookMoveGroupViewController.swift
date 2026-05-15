import UIKit

final class BookMoveGroupViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Item: Hashable {
        case ungrouped
        case group(BookGroupSummary)
    }

    var onGroupSelected: ((UUID?) -> Void)?

    private let groups: [BookGroupSummary]
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

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
        title = "\u{79FB}\u{52A8}\u{5230}\u{5206}\u{7EC4}"
        view.backgroundColor = YominkTheme.background
        configureCollectionView()
        configureDataSource()
        applySnapshot()
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
            cell.accessories = [.disclosureIndicator()]

            switch item {
            case .ungrouped:
                content.text = "\u{672A}\u{5206}\u{7EC4}"
                content.secondaryText = nil
                content.image = UIImage(systemName: "tray")
            case .group(let summary):
                content.text = summary.group.name
                content.secondaryText = "\(summary.bookCount)"
                content.image = UIImage(systemName: "folder")
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
        snapshot.appendItems([.ungrouped] + groups.map(Item.group), toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }
}

extension BookMoveGroupViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        let groupID: UUID?
        switch item {
        case .ungrouped:
            groupID = nil
        case .group(let summary):
            groupID = summary.group.id
        }

        dismiss(animated: true) { [onGroupSelected] in
            onGroupSelected?(groupID)
        }
    }
}
