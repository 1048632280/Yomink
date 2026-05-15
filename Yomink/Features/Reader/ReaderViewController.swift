import UIKit

final class ReaderViewController: UIViewController {
    private enum Section {
        case main
    }

    private let book: BookRecord
    private let openingService: ReaderOpeningService
    private let pagingService: ReaderPagingService
    private let bookmarkService: ReadingBookmarkService
    private let chapterService: ReadingChapterService
    private let readingSettingsStore: ReadingSettingsStore
    private let progressStore: ReadingProgressStore
    private let collectionView: UICollectionView
    private let statusBarView = ReaderStatusBarView()

    private var dataSource: UICollectionViewDiffableDataSource<Section, ReaderPage>?
    private var pages: [ReaderPage] = []
    private var currentPage: ReaderPage?
    private var openingTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var didStartOpening = false
    private var didReachEndOfBook = false
    private var activeSettings = ReadingSettings.standard
    private var pagingGeneration = 0
    private let maximumResidentPages = 12

    init(
        book: BookRecord,
        openingService: ReaderOpeningService,
        pagingService: ReaderPagingService,
        bookmarkService: ReadingBookmarkService,
        chapterService: ReadingChapterService,
        readingSettingsStore: ReadingSettingsStore,
        progressStore: ReadingProgressStore
    ) {
        self.book = book
        self.openingService = openingService
        self.pagingService = pagingService
        self.bookmarkService = bookmarkService
        self.chapterService = chapterService
        self.readingSettingsStore = readingSettingsStore
        self.progressStore = progressStore

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        configureNavigationItems()
        applyTheme(activeSettings.theme)
        configureCollectionView()
        configureStatusBar()
        configureDataSource()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveCurrentProgressForBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        pagingService.removeCachedPages()
        trimResidentPagesAroundCurrent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
        openFirstPageIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveCurrentProgress()
    }

    deinit {
        openingTask?.cancel()
        nextPageTask?.cancel()
        chapterService.cancelParsing(bookID: book.id)
        NotificationCenter.default.removeObserver(self)
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delegate = self
        collectionView.register(ReaderPageCell.self, forCellWithReuseIdentifier: ReaderPageCell.reuseIdentifier)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureNavigationItems() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(showReadingSettings)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "bookmark"),
                style: .plain,
                target: self,
                action: #selector(addBookmark)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: self,
                action: #selector(showCatalogAndBookmarks)
            )
        ]
    }

    private func configureStatusBar() {
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBarView)
        NSLayoutConstraint.activate([
            statusBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, ReaderPage>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, page in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ReaderPageCell.reuseIdentifier,
                    for: indexPath
                  ) as? ReaderPageCell else {
                return UICollectionViewCell()
            }
            cell.configure(page: page, settings: activeSettings)
            return cell
        }
    }

    private func applyTheme(_ theme: ReadingTheme) {
        let palette = ReadingThemePalette.palette(for: theme)
        view.backgroundColor = palette.background
        collectionView.backgroundColor = palette.background
        statusBarView.applyTheme(theme)
    }

    @objc private func showReadingSettings() {
        updateCurrentPageFromVisiblePage()
        var settings = activeSettings
        settings.layout.viewportSize = collectionView.bounds.size

        let settingsViewController = ReaderSettingsViewController(settings: settings)
        settingsViewController.onApply = { [weak self] newSettings in
            self?.applyReadingSettings(newSettings)
        }

        let navigationController = UINavigationController(rootViewController: settingsViewController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    private func applyReadingSettings(_ settings: ReadingSettings) {
        updateCurrentPageFromVisiblePage()
        let preferredByteOffset = currentPage?.startByteOffset
        activeSettings = settings.normalized(viewportSize: collectionView.bounds.size)
        readingSettingsStore.save(activeSettings)
        pagingService.removeCachedPages()
        applyTheme(activeSettings.theme)
        refreshVisibleCellsForActiveSettings()
        openPage(preferredByteOffset: preferredByteOffset)
    }

    @objc private func addBookmark() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try await bookmarkService.addBookmark(bookID: book.id, page: currentPage)
                showTransientNotice(title: "\u{5DF2}\u{6DFB}\u{52A0}\u{4E66}\u{7B7E}")
            } catch {
                showTransientNotice(title: "\u{4E66}\u{7B7E}\u{4FDD}\u{5B58}\u{5931}\u{8D25}")
            }
        }
    }

    @objc private func showCatalogAndBookmarks() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let chapters = try await chapterService.chapters(bookID: book.id)
                let bookmarks = try await bookmarkService.bookmarks(bookID: book.id)
                presentCatalogAndBookmarks(chapters: chapters, bookmarks: bookmarks)
            } catch {
                showTransientNotice(title: "\u{76EE}\u{5F55}\u{52A0}\u{8F7D}\u{5931}\u{8D25}")
            }
        }
    }

    private func presentCatalogAndBookmarks(chapters: [ReadingChapter], bookmarks: [ReadingBookmark]) {
        let listViewController = CatalogAndBookmarksViewController(
            chapters: chapters,
            bookmarks: bookmarks
        )
        listViewController.onChapterSelected = { [weak self] chapter in
            self?.jumpToChapter(chapter)
        }
        listViewController.onBookmarkSelected = { [weak self] bookmark in
            self?.jumpToBookmark(bookmark)
        }
        let navigationController = UINavigationController(rootViewController: listViewController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    private func jumpToChapter(_ chapter: ReadingChapter) {
        jumpToByteOffset(chapter.byteOffset)
    }

    private func jumpToBookmark(_ bookmark: ReadingBookmark) {
        jumpToByteOffset(bookmark.byteOffset)
    }

    private func jumpToByteOffset(_ byteOffset: UInt64) {
        saveCurrentProgress()
        progressStore.remember(
            ReadingProgress(
                bookID: book.id,
                byteOffset: byteOffset,
                updatedAt: Date()
            )
        )
        progressStore.flushPendingProgress()
        pagingService.removeCachedPages()
        openPage(preferredByteOffset: byteOffset)
    }

    private func refreshVisibleCellsForActiveSettings() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard pages.indices.contains(indexPath.item),
                  let cell = collectionView.cellForItem(at: indexPath) as? ReaderPageCell else {
                continue
            }
            cell.configure(page: pages[indexPath.item], settings: activeSettings)
        }
    }

    private func openFirstPageIfNeeded() {
        guard !didStartOpening,
              collectionView.bounds.width > 1,
              collectionView.bounds.height > 1 else {
            return
        }

        didStartOpening = true
        activeSettings = readingSettingsStore.load().normalized(viewportSize: collectionView.bounds.size)
        applyTheme(activeSettings.theme)
        openPage(preferredByteOffset: nil)
    }

    private func openPage(preferredByteOffset: UInt64?) {
        openingTask?.cancel()
        nextPageTask?.cancel()
        nextPageTask = nil
        pages = []
        currentPage = nil
        applyPagesSnapshot()
        didReachEndOfBook = false
        pagingGeneration += 1
        let generation = pagingGeneration
        let request = ReaderOpeningRequest(
            bookID: book.id,
            viewportSize: collectionView.bounds.size,
            layout: activeSettings.layout,
            preferredByteOffset: preferredByteOffset
        )

        openingTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await openingService.openFirstPage(request)
                guard pagingGeneration == generation else {
                    return
                }
                openingTask = nil
                applyInitialPage(result.page)
                collectionView.setContentOffset(.zero, animated: false)
                loadNextPageIfNeeded()
            } catch {
                guard pagingGeneration == generation else {
                    return
                }
                openingTask = nil
                showOpeningError()
            }
        }
    }

    private func applyInitialPage(_ page: ReaderPage) {
        pages = [page]
        currentPage = page
        applyPagesSnapshot()
        refreshVisibleCellsForActiveSettings()
        updateSessionState(isLoadingNextPage: false)
        chapterService.scheduleParsing(bookID: book.id)
    }

    private func appendPage(_ page: ReaderPage) {
        guard !pages.contains(where: { $0.startByteOffset == page.startByteOffset }) else {
            return
        }
        pages.append(page)
        let removedPrefixCount = trimResidentPagesIfNeeded()
        applyPagesSnapshot()
        adjustContentOffsetAfterRemovingPrefix(removedPrefixCount)
        refreshVisibleCellsForActiveSettings()
        updateSessionState(isLoadingNextPage: false)
    }

    private func applyPagesSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ReaderPage>()
        snapshot.appendSections([.main])
        snapshot.appendItems(pages, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func loadNextPageIfNeeded() {
        guard !didReachEndOfBook,
              nextPageTask == nil,
              let lastPage = pages.last,
              lastPage.endByteOffset < book.fileSize else {
            return
        }

        let request = ReaderPageRequest(
            bookID: book.id,
            startByteOffset: lastPage.endByteOffset,
            pageIndex: lastPage.pageIndex + 1,
            layout: activeSettings.layout
        )
        let generation = pagingGeneration

        nextPageTask = Task { [weak self] in
            guard let self else {
                return
            }

            updateSessionState(isLoadingNextPage: true)
            do {
                let nextPage = try await pagingService.page(request)
                guard pagingGeneration == generation else {
                    return
                }
                nextPageTask = nil
                guard let nextPage else {
                    didReachEndOfBook = true
                    updateSessionState(isLoadingNextPage: false)
                    return
                }
                appendPage(nextPage)
            } catch {
                guard pagingGeneration == generation else {
                    return
                }
                nextPageTask = nil
                updateSessionState(isLoadingNextPage: false)
            }
        }
    }

    private func saveCurrentProgress() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage else {
            return
        }

        progressStore.remember(
            ReadingProgress(
                bookID: currentPage.bookID,
                byteOffset: currentPage.startByteOffset,
                updatedAt: Date()
            )
        )
        progressStore.flushPendingProgress()
    }

    @objc private func saveCurrentProgressForBackground() {
        saveCurrentProgress()
    }

    private func updateCurrentPageFromVisiblePage() {
        guard collectionView.bounds.width > 1 else {
            return
        }

        let visibleCenter = CGPoint(
            x: collectionView.contentOffset.x + collectionView.bounds.midX,
            y: collectionView.bounds.midY
        )
        guard let indexPath = collectionView.indexPathForItem(at: visibleCenter),
              pages.indices.contains(indexPath.item) else {
            return
        }

        currentPage = pages[indexPath.item]
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
    }

    private func trimResidentPagesIfNeeded() -> Int {
        guard pages.count > maximumResidentPages,
              let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage),
              currentIndex > 3 else {
            return 0
        }

        let overflow = pages.count - maximumResidentPages
        let removableBeforeCurrent = max(0, currentIndex - 3)
        let removeCount = min(overflow, removableBeforeCurrent)
        guard removeCount > 0 else {
            return 0
        }

        pages.removeFirst(removeCount)
        return removeCount
    }

    private func trimResidentPagesAroundCurrent() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let lowerBound = max(0, currentIndex - 1)
        let upperBound = min(pages.count, currentIndex + 2)
        let removePrefixCount = lowerBound
        pages = Array(pages[lowerBound..<upperBound])
        applyPagesSnapshot()
        adjustContentOffsetAfterRemovingPrefix(removePrefixCount)
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
    }

    private func adjustContentOffsetAfterRemovingPrefix(_ removePrefixCount: Int) {
        guard removePrefixCount > 0 else {
            return
        }
        let pageWidth = collectionView.bounds.width
        guard pageWidth > 0 else {
            return
        }

        let adjustedOffset = CGPoint(
            x: max(0, collectionView.contentOffset.x - CGFloat(removePrefixCount) * pageWidth),
            y: collectionView.contentOffset.y
        )
        collectionView.setContentOffset(adjustedOffset, animated: false)
    }

    private func updateSessionState(isLoadingNextPage: Bool) {
        guard let currentPage else {
            return
        }

        statusBarView.configure(
            state: ReaderSessionState(
                bookID: currentPage.bookID,
                currentPageIndex: currentPage.pageIndex,
                residentPageCount: pages.count,
                startByteOffset: currentPage.startByteOffset,
                endByteOffset: currentPage.endByteOffset,
                fileSize: book.fileSize,
                isLoadingNextPage: isLoadingNextPage,
                didReachEndOfBook: didReachEndOfBook
            )
        )
    }

    private func showTransientNotice(title: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak alert] in
            alert?.dismiss(animated: true)
        }
    }

    private func showOpeningError() {
        let alert = UIAlertController(
            title: "\u{6253}\u{5F00}\u{5931}\u{8D25}",
            message: "\u{65E0}\u{6CD5}\u{6253}\u{5F00}\u{8FD9}\u{672C} TXT\u{3002}",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        present(alert, animated: true)
    }
}

extension ReaderViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard pages.indices.contains(indexPath.item) else {
            return
        }

        currentPage = pages[indexPath.item]
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
        if indexPath.item >= pages.count - 2 {
            loadNextPageIfNeeded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentPageFromVisiblePage()
        loadNextPageIfNeeded()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }
}
