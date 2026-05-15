import UIKit

final class CatalogAndBookmarksViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Segment: Int {
        case chapters
        case bookmarks
    }

    private enum Item: Hashable {
        case chapter(ReadingChapter)
        case bookmark(ReadingBookmark)
        case empty(String)
    }

    var onChapterSelected: ((ReadingChapter) -> Void)?
    var onBookmarkSelected: ((ReadingBookmark) -> Void)?

    private let chapters: [ReadingChapter]
    private let bookmarks: [ReadingBookmark]
    private let segmentedControl = UISegmentedControl(
        items: ["\u{76EE}\u{5F55}", "\u{4E66}\u{7B7E}"]
    )
    private var selectedSegment: Segment = .chapters
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

    init(chapters: [ReadingChapter], bookmarks: [ReadingBookmark]) {
        self.chapters = chapters
        self.bookmarks = bookmarks
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = YominkTheme.background
        configureNavigationItems()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureNavigationItems() {
        segmentedControl.selectedSegmentIndex = selectedSegment.rawValue
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        navigationItem.titleView = segmentedControl
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "\u{5E95}\u{90E8}",
                style: .plain,
                target: self,
                action: #selector(scrollToBottom)
            ),
            UIBarButtonItem(
                title: "\u{9876}\u{90E8}",
                style: .plain,
                target: self,
                action: #selector(scrollToTop)
            )
        ]
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
            cell.accessories = []

            switch item {
            case .chapter(let chapter):
                content.text = chapter.title
                content.secondaryText = "\u{4F4D}\u{7F6E} \(chapter.byteOffset)"
                cell.accessories = [.disclosureIndicator()]
            case .bookmark(let bookmark):
                content.text = bookmark.title
                content.secondaryText = "\u{4F4D}\u{7F6E} \(bookmark.byteOffset)"
                cell.accessories = [.disclosureIndicator()]
            case .empty(let message):
                content.text = message
                content.secondaryText = nil
            }

            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText
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
        snapshot.appendItems(itemsForSelectedSegment(), toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func itemsForSelectedSegment() -> [Item] {
        switch selectedSegment {
        case .chapters:
            return chapters.isEmpty
                ? [.empty("\u{76EE}\u{5F55}\u{89E3}\u{6790}\u{4E2D}")]
                : chapters.map(Item.chapter)
        case .bookmarks:
            return bookmarks.isEmpty
                ? [.empty("\u{6682}\u{65E0}\u{4E66}\u{7B7E}")]
                : bookmarks.map(Item.bookmark)
        }
    }

    @objc private func segmentChanged() {
        selectedSegment = Segment(rawValue: segmentedControl.selectedSegmentIndex) ?? .chapters
        applySnapshot()
        scrollToTop()
    }

    @objc private func scrollToTop() {
        guard collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: true
        )
    }

    @objc private func scrollToBottom() {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            return
        }
        collectionView.scrollToItem(
            at: IndexPath(item: itemCount - 1, section: 0),
            at: .bottom,
            animated: true
        )
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension CatalogAndBookmarksViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        dismiss(animated: true) { [onChapterSelected, onBookmarkSelected] in
            switch item {
            case .chapter(let chapter):
                onChapterSelected?(chapter)
            case .bookmark(let bookmark):
                onBookmarkSelected?(bookmark)
            case .empty:
                break
            }
        }
    }
}
