import UIKit

final class BookshelfGroupDrawerViewController: UIViewController {
    private enum Section {
        case main
        case actions
    }

    private enum Item: Hashable {
        case all(Int)
        case ungrouped(Int)
        case group(BookGroupSummary)
        case manage
    }

    var onFilterSelected: ((BookshelfGroupFilter) -> Void)?
    var onManageGroups: (() -> Void)?

    private let groupList: BookGroupList
    private let selectedFilter: BookshelfGroupFilter
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

    init(groupList: BookGroupList, selectedFilter: BookshelfGroupFilter) {
        self.groupList = groupList
        self.selectedFilter = selectedFilter
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{4E66}\u{67B6}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
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
        let selectedFilter = self.selectedFilter
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = UIListContentConfiguration.valueCell()
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText
            cell.accessories = Self.accessories(for: item, selectedFilter: selectedFilter)

            switch item {
            case .all(let count):
                content.text = "\u{5168}\u{90E8}\u{4E66}\u{7C4D}"
                content.secondaryText = "\(count)"
                content.image = UIImage(systemName: "books.vertical")
            case .ungrouped(let count):
                content.text = "\u{672A}\u{5206}\u{7EC4}"
                content.secondaryText = "\(count)"
                content.image = UIImage(systemName: "tray")
            case .group(let summary):
                content.text = summary.group.name
                content.secondaryText = "\(summary.bookCount)"
                content.image = UIImage(systemName: "folder")
            case .manage:
                content.text = "\u{7BA1}\u{7406}\u{5206}\u{7EC4}"
                content.secondaryText = nil
                content.image = UIImage(systemName: "slider.horizontal.3")
                cell.accessories = [.disclosureIndicator()]
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
        snapshot.appendSections([.main, .actions])
        snapshot.appendItems(
            [.all(groupList.totalBookCount), .ungrouped(groupList.ungroupedBookCount)]
                + groupList.groups.map(Item.group),
            toSection: .main
        )
        snapshot.appendItems([.manage], toSection: .actions)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private static func accessories(
        for item: Item,
        selectedFilter: BookshelfGroupFilter
    ) -> [UICellAccessory] {
        switch (item, selectedFilter) {
        case (.all, .all), (.ungrouped, .ungrouped):
            return [.checkmark()]
        case (.group(let summary), .group(let selectedGroupID)) where summary.group.id == selectedGroupID:
            return [.checkmark()]
        default:
            return []
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension BookshelfGroupDrawerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .all:
            dismiss(animated: true) { [onFilterSelected] in
                onFilterSelected?(.all)
            }
        case .ungrouped:
            dismiss(animated: true) { [onFilterSelected] in
                onFilterSelected?(.ungrouped)
            }
        case .group(let summary):
            dismiss(animated: true) { [onFilterSelected] in
                onFilterSelected?(.group(summary.group.id))
            }
        case .manage:
            dismiss(animated: true) { [onManageGroups] in
                onManageGroups?()
            }
        }
    }
}
