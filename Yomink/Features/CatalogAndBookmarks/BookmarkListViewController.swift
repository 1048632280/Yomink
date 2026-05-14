import UIKit

final class BookmarkListViewController: UIViewController {
    private enum Section {
        case main
    }

    var onBookmarkSelected: ((ReadingBookmark) -> Void)?

    private let bookmarks: [ReadingBookmark]
    private var dataSource: UICollectionViewDiffableDataSource<Section, ReadingBookmark>?

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

    init(bookmarks: [ReadingBookmark]) {
        self.bookmarks = bookmarks
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{4E66}\u{7B7E}"
        view.backgroundColor = YominkTheme.background
        configureNavigationItems()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
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
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, ReadingBookmark> { cell, _, bookmark in
            var content = UIListContentConfiguration.subtitleCell()
            content.text = bookmark.title
            content.secondaryText = "\u{4F4D}\u{7F6E} \(bookmark.byteOffset)"
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, ReadingBookmark>(
            collectionView: collectionView
        ) { collectionView, indexPath, bookmark in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: bookmark)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ReadingBookmark>()
        snapshot.appendSections([.main])
        snapshot.appendItems(bookmarks, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension BookmarkListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let bookmark = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }
        dismiss(animated: true) { [onBookmarkSelected] in
            onBookmarkSelected?(bookmark)
        }
    }
}
