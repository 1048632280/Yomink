import UIKit

final class CatalogAndBookmarksViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Segment: Int {
        case chapters
        case bookmarks
    }

    private enum EdgeJumpTarget {
        case top
        case bottom
    }

    private enum Item: Hashable {
        case chapter(ReadingChapter, displayIndex: Int)
        case bookmark(ReadingBookmark)
        case empty(String)
    }

    var onChapterSelected: ((ReadingChapter) -> Void)?
    var onBookmarkSelected: ((ReadingBookmark) -> Void)?
    var onBookmarkDeleteRequested: ((ReadingBookmark, @escaping (Bool) -> Void) -> Void)?

    private let chapters: [ReadingChapter]
    private var bookmarks: [ReadingBookmark]
    private let currentByteOffset: UInt64?
    private let segmentedControl = UISegmentedControl(
        items: ["\u{76EE}\u{5F55}", "\u{4E66}\u{7B7E}"]
    )
    private var selectedSegment: Segment = .chapters
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    private var edgeJumpTarget: EdgeJumpTarget = .bottom
    private var lastContentOffsetY: CGFloat = 0
    private var chapterSearchText = ""
    private var didScrollToCurrentChapter = false
    private let searchBar = UISearchBar(frame: .zero)
    private var searchBarHeightConstraint: NSLayoutConstraint?
    private lazy var edgeJumpButton = UIBarButtonItem(
        title: "\u{5E95}\u{90E8}",
        style: .plain,
        target: self,
        action: #selector(edgeJumpTapped)
    )

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.backgroundColor = YominkTheme.background
            configuration.showsSeparators = true
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.swipeActionsConfiguration(for: indexPath)
            }
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = YominkTheme.background
        return collectionView
    }()

    init(chapters: [ReadingChapter], bookmarks: [ReadingBookmark], currentByteOffset: UInt64?) {
        self.chapters = chapters
        self.bookmarks = bookmarks
        self.currentByteOffset = currentByteOffset
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
        configureSearchBar()
        configureCollectionView()
        configureDataSource()
        updateSearchBarVisibility(animated: false)
        applySnapshot()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToCurrentChapterIfNeeded()
    }

    private func configureNavigationItems() {
        segmentedControl.selectedSegmentIndex = selectedSegment.rawValue
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        navigationItem.titleView = segmentedControl
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(goBack)
        )
        navigationItem.rightBarButtonItem = edgeJumpButton
        setEdgeJumpTarget(.bottom)
    }

    private func configureCollectionView() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        view.addSubview(collectionView)
        collectionView.delegate = self
        let searchBarHeightConstraint = searchBar.heightAnchor.constraint(equalToConstant: 52)
        self.searchBarHeightConstraint = searchBarHeightConstraint
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchBarHeightConstraint,

            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "\u{641C}\u{7D22}"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.showsCancelButton = false
    }

    private func configureDataSource() {
        let currentChapterID = currentChapterIndex().map { chapters[$0].id }
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = UIListContentConfiguration.subtitleCell()
            cell.accessories = []

            switch item {
            case .chapter(let chapter, let displayIndex):
                content.text = "\(displayIndex).\(chapter.title)"
                content.secondaryText = nil
                let isCurrentChapter = currentChapterID.map { $0 == chapter.id } ?? false
                content.textProperties.color = isCurrentChapter ? .systemRed : YominkTheme.primaryText
                cell.accessories = [.disclosureIndicator()]
            case .bookmark(let bookmark):
                content.text = bookmark.title
                content.secondaryText = "\u{4F4D}\u{7F6E} \(bookmark.byteOffset)"
                content.image = UIImage(systemName: "bookmark.fill")
                content.imageProperties.tintColor = YominkTheme.primaryText
                content.textProperties.color = YominkTheme.primaryText
                cell.accessories = [.disclosureIndicator()]
            case .empty(let message):
                content.text = message
                content.secondaryText = nil
                content.textProperties.color = YominkTheme.primaryText
            }

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
        applySnapshot(animatingDifferences: false)
    }

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(itemsForSelectedSegment(), toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func itemsForSelectedSegment() -> [Item] {
        switch selectedSegment {
        case .chapters:
            let filteredChapters = filteredChapters()
            return filteredChapters.isEmpty
                ? [.empty(chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\u{76EE}\u{5F55}\u{89E3}\u{6790}\u{4E2D}" : "\u{672A}\u{627E}\u{5230}\u{5339}\u{914D}\u{76EE}\u{5F55}")]
                : filteredChapters.map { item in
                    Item.chapter(item.chapter, displayIndex: item.displayIndex)
                }
        case .bookmarks:
            return bookmarks.isEmpty
                ? [.empty("\u{6682}\u{65E0}\u{4E66}\u{7B7E}")]
                : bookmarks.map(Item.bookmark)
        }
    }

    private func filteredChapters() -> [(chapter: ReadingChapter, displayIndex: Int)] {
        let indexedChapters = chapters.enumerated().map { index, chapter in
            (chapter: chapter, displayIndex: index + 1)
        }
        let query = chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return indexedChapters
        }
        return indexedChapters.filter { item in
            item.chapter.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    @objc private func segmentChanged() {
        selectedSegment = Segment(rawValue: segmentedControl.selectedSegmentIndex) ?? .chapters
        updateSearchBarVisibility(animated: true)
        applySnapshot()
        scrollToTop(animated: false)
        setEdgeJumpTarget(.bottom)
    }

    private func updateSearchBarVisibility(animated: Bool) {
        let shouldShowSearchBar = selectedSegment == .chapters
        if shouldShowSearchBar {
            searchBar.isHidden = false
        } else {
            chapterSearchText = ""
            searchBar.text = nil
            searchBar.showsCancelButton = false
            searchBar.resignFirstResponder()
        }
        searchBarHeightConstraint?.constant = shouldShowSearchBar ? 52 : 0
        let layoutUpdate = {
            self.view.layoutIfNeeded()
            self.searchBar.isHidden = !shouldShowSearchBar
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: layoutUpdate)
        } else {
            layoutUpdate()
        }
    }

    private func currentChapterIndex() -> Int? {
        guard let currentByteOffset,
              !chapters.isEmpty else {
            return nil
        }
        return chapters.lastIndex { $0.byteOffset <= currentByteOffset }
    }

    private func scrollToCurrentChapterIfNeeded() {
        guard !didScrollToCurrentChapter,
              selectedSegment == .chapters,
              chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let currentIndex = currentChapterIndex(),
              collectionView.numberOfItems(inSection: 0) > currentIndex else {
            return
        }
        didScrollToCurrentChapter = true
        collectionView.scrollToItem(
            at: IndexPath(item: currentIndex, section: 0),
            at: .centeredVertically,
            animated: false
        )
        lastContentOffsetY = collectionView.contentOffset.y
        updateEdgeJumpTargetForScroll()
    }

    private func scrollToTop(animated: Bool) {
        guard collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: animated
        )
        lastContentOffsetY = collectionView.contentOffset.y
    }

    private func scrollToBottom(animated: Bool) {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            return
        }
        collectionView.scrollToItem(
            at: IndexPath(item: itemCount - 1, section: 0),
            at: .bottom,
            animated: animated
        )
        lastContentOffsetY = collectionView.contentOffset.y
    }

    @objc private func edgeJumpTapped() {
        switch edgeJumpTarget {
        case .bottom:
            scrollToBottom(animated: true)
            setEdgeJumpTarget(.top)
        case .top:
            scrollToTop(animated: true)
            setEdgeJumpTarget(.bottom)
        }
    }

    private func setEdgeJumpTarget(_ target: EdgeJumpTarget) {
        edgeJumpTarget = target
        edgeJumpButton.title = target == .bottom ? "\u{5E95}\u{90E8}" : "\u{9876}\u{90E8}"
    }

    private func updateEdgeJumpTargetForScroll() {
        let offsetY = collectionView.contentOffset.y
        let minOffsetY = -collectionView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        )
        let threshold: CGFloat = 8

        if offsetY <= minOffsetY + threshold {
            setEdgeJumpTarget(.bottom)
        } else if offsetY >= maxOffsetY - threshold {
            setEdgeJumpTarget(.top)
        } else if offsetY > lastContentOffsetY + 1 {
            setEdgeJumpTarget(.bottom)
        } else if offsetY < lastContentOffsetY - 1 {
            setEdgeJumpTarget(.top)
        }
        lastContentOffsetY = offsetY
    }

    @objc private func goBack() {
        closePage()
    }

    private func closePage(completion: (() -> Void)? = nil) {
        if let navigationController,
           navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
            completion?()
        } else {
            dismiss(animated: true, completion: completion)
        }
    }

    private func swipeActionsConfiguration(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard selectedSegment == .bookmarks,
              let item = dataSource?.itemIdentifier(for: indexPath),
              case .bookmark(let bookmark) = item else {
            return nil
        }

        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "\u{5220}\u{9664}"
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            self.requestDelete(bookmark, completion: completion)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func requestDelete(_ bookmark: ReadingBookmark, completion: @escaping (Bool) -> Void) {
        guard let onBookmarkDeleteRequested else {
            removeBookmark(bookmark)
            completion(true)
            return
        }

        onBookmarkDeleteRequested(bookmark) { [weak self] didDelete in
            DispatchQueue.main.async {
                if didDelete {
                    self?.removeBookmark(bookmark)
                }
                completion(didDelete)
            }
        }
    }

    private func removeBookmark(_ bookmark: ReadingBookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else {
            return
        }
        bookmarks.remove(at: index)
        applySnapshot(animatingDifferences: true)
    }
}

extension CatalogAndBookmarksViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        closePage { [onChapterSelected, onBookmarkSelected] in
            switch item {
            case .chapter(let chapter, _):
                onChapterSelected?(chapter)
            case .bookmark(let bookmark):
                onBookmarkSelected?(bookmark)
            case .empty:
                break
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateEdgeJumpTargetForScroll()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateEdgeJumpTargetForScroll()
    }
}

extension CatalogAndBookmarksViewController: UISearchBarDelegate {
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        chapterSearchText = searchText
        guard selectedSegment == .chapters else {
            return
        }
        applySnapshot(animatingDifferences: true)
        scrollToTop(animated: false)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        chapterSearchText = ""
        searchBar.text = nil
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
        guard selectedSegment == .chapters else {
            return
        }
        applySnapshot(animatingDifferences: true)
        scrollToTop(animated: false)
    }
}
