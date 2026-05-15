import UIKit

final class BookshelfRecentViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Item: Hashable {
        case message(String)
        case book(BookshelfBookItem)
    }

    var onBookSelected: ((BookRecord) -> Void)?

    private let items: [BookshelfBookItem]
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

    init(items: [BookshelfBookItem]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{8DB3}\u{8FF9}"
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
            var content = UIListContentConfiguration.subtitleCell()
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText

            switch item {
            case .message(let message):
                content.text = message
                content.secondaryText = nil
                content.image = UIImage(systemName: "clock")
                cell.accessories = []
            case .book(let item):
                content.text = item.book.title
                content.secondaryText = Self.subtitle(for: item)
                content.image = UIImage(systemName: "book.closed")
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
        snapshot.appendSections([.main])
        snapshot.appendItems(
            items.isEmpty
                ? [.message("\u{6682}\u{65E0}\u{9605}\u{8BFB}\u{8DB3}\u{8FF9}")]
                : items.map(Item.book),
            toSection: .main
        )
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private static func subtitle(for item: BookshelfBookItem) -> String {
        let percent = Int((item.readingProgress * 100).rounded())
        guard let lastReadAt = item.book.lastReadAt else {
            return "\(percent)%"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "\(percent)% · \(formatter.localizedString(for: lastReadAt, relativeTo: Date()))"
    }
}

extension BookshelfRecentViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let bookItem) = item else {
            return
        }
        onBookSelected?(bookItem.book)
    }
}
