import UIKit

final class ReaderViewController: UIViewController {
    private enum Section {
        case main
    }

    private var book: BookRecord
    private let openingService: ReaderOpeningService
    private let pagingService: ReaderPagingService
    private let bookmarkService: ReadingBookmarkService
    private let chapterService: ReadingChapterService
    private let searchIndexService: SearchIndexService
    private let contentFilterService: ContentFilterService
    private let bookDetailService: BookDetailService
    private let tapAreaSettingsStore: TapAreaSettingsStore
    private let readingSettingsStore: ReadingSettingsStore
    private let progressStore: ReadingProgressStore
    private let collectionView: UICollectionView
    private let chromeView = ReaderChromeView()
    private let statusBarView = ReaderStatusBarView()
    private let autoReadPanelView = AutoReadSpeedPanelView()

    private var dataSource: UICollectionViewDiffableDataSource<Section, ReaderPage>?
    private var pages: [ReaderPage] = []
    private var currentPage: ReaderPage?
    private var chapters: [ReadingChapter] = []
    private var contentFilterRules: [ContentFilterRule] = []
    private var tapAreaSettings = TapAreaSettings.standard
    private var openingTask: Task<Void, Never>?
    private var previousPageTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var chapterRefreshTask: Task<Void, Never>?
    private var backgroundWorkResumeTask: Task<Void, Never>?
    private var didStartOpening = false
    private var didReachEndOfBook = false
    private var isLoadingNextPage = false
    private var isChromeVisible = false
    private var isAutoReading = false
    private var isAutoReadPanelVisible = false
    private var autoReadSpeed: CGFloat = 36
    private var autoReadTickTask: Task<Void, Never>?
    private var activeSettings = ReadingSettings.standard
    private var preferredInterfaceStyle: UIUserInterfaceStyle = .unspecified
    private var pagingGeneration = 0
    private let maximumResidentPages = 12
    private var usesVerticalScrolling: Bool {
        isAutoReading || activeSettings.pageTurnMode == .verticalScroll
    }

    init(
        book: BookRecord,
        openingService: ReaderOpeningService,
        pagingService: ReaderPagingService,
        bookmarkService: ReadingBookmarkService,
        chapterService: ReadingChapterService,
        searchIndexService: SearchIndexService,
        contentFilterService: ContentFilterService,
        bookDetailService: BookDetailService,
        tapAreaSettingsStore: TapAreaSettingsStore,
        readingSettingsStore: ReadingSettingsStore,
        progressStore: ReadingProgressStore
    ) {
        self.book = book
        self.openingService = openingService
        self.pagingService = pagingService
        self.bookmarkService = bookmarkService
        self.chapterService = chapterService
        self.searchIndexService = searchIndexService
        self.contentFilterService = contentFilterService
        self.bookDetailService = bookDetailService
        self.tapAreaSettingsStore = tapAreaSettingsStore
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

    override var prefersHomeIndicatorAutoHidden: Bool {
        activeSettings.autoHideHomeIndicator
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = book.title
        applyTheme(activeSettings.theme)
        configureCollectionView()
        configureDataSource()
        configureStatusBarView()
        configureAutoReadPanel()
        configureChrome()
        configureGestures()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveCurrentProgressForBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        applyReaderPreferences()
        scheduleBackgroundWorkResume(after: 1.5)
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
        stopAutoReading()
        pauseBackgroundWork()
        saveCurrentProgress()
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isBatteryMonitoringEnabled = false
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    deinit {
        autoReadTickTask?.cancel()
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        openingTask?.cancel()
        previousPageTask?.cancel()
        nextPageTask?.cancel()
        chapterRefreshTask?.cancel()
        backgroundWorkResumeTask?.cancel()
        chapterService.cancelParsing(bookID: book.id)
        searchIndexService.cancelIndexing(bookID: book.id)
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
            cell.configure(page: page, settings: activeSettings, filterRules: contentFilterRules)
            return cell
        }
    }

    private func configureStatusBarView() {
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.isHidden = true
        view.addSubview(statusBarView)
        NSLayoutConstraint.activate([
            statusBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            statusBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configureAutoReadPanel() {
        view.addSubview(autoReadPanelView)
        NSLayoutConstraint.activate([
            autoReadPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            autoReadPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            autoReadPanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        autoReadPanelView.configure(speed: autoReadSpeed, theme: activeSettings.theme)
        autoReadPanelView.onSpeedChanged = { [weak self] speed in
            self?.autoReadSpeed = speed
        }
        autoReadPanelView.onExit = { [weak self] in
            self?.stopAutoReading()
        }
    }

    private func configureChrome() {
        view.addSubview(chromeView)
        NSLayoutConstraint.activate([
            chromeView.topAnchor.constraint(equalTo: view.topAnchor),
            chromeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chromeView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        chromeView.onAction = { [weak self] action in
            self?.handleChromeAction(action)
        }
        chromeView.onBackgroundTap = { [weak self] in
            self?.setChromeVisible(false, animated: true)
        }
        chromeView.onProgressPreview = { [weak self] progress in
            self?.progressPreviewText(for: progress) ?? "0.0%"
        }
        chromeView.onProgressCommit = { [weak self] progress in
            self?.jumpToProgress(progress)
        }
        updateChrome()
    }

    private func configureGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleReaderTap(_:)))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
    }

    private func applyTheme(_ theme: ReadingTheme) {
        let palette = ReadingThemePalette.palette(for: theme)
        view.backgroundColor = palette.background
        collectionView.backgroundColor = palette.background
        statusBarView.applyTheme(theme)
        autoReadPanelView.configure(speed: autoReadSpeed, theme: theme)
        chromeView.configure(title: book.title, state: currentSessionState(), theme: theme)
    }

    @objc private func showReadingSettings() {
        stopAutoReading()
        setChromeVisible(false, animated: true)
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
        applyReaderPreferences()
        applyTheme(activeSettings.theme)
        refreshVisibleCellsForActiveSettings()
        openPage(preferredByteOffset: preferredByteOffset)
    }

    private func applyReaderPreferences() {
        UIApplication.shared.isIdleTimerDisabled = activeSettings.keepScreenAwake
        UIDevice.current.isBatteryMonitoringEnabled = activeSettings.statusBarItems.contains(.battery)
            || activeSettings.statusBarItems.contains(.batteryPercent)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        configureCollectionViewForActiveSettings()
        updateStatusBar()
    }

    private func configureCollectionViewForActiveSettings() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }

        guard !isAutoReading else {
            configureCollectionViewForAutoReading()
            return
        }

        switch activeSettings.pageTurnMode {
        case .horizontal, .simulatedCurl:
            layout.scrollDirection = .horizontal
            collectionView.isPagingEnabled = true
            collectionView.alwaysBounceVertical = false
        case .verticalScroll:
            layout.scrollDirection = .vertical
            collectionView.isPagingEnabled = false
            collectionView.alwaysBounceVertical = true
        }
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
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
                let result = try await bookmarkService.addBookmark(bookID: book.id, page: currentPage)
                showTransientNotice(
                    title: result.didCreate
                        ? "\u{5DF2}\u{6DFB}\u{52A0}\u{4E66}\u{7B7E}"
                        : "\u{5F53}\u{524D}\u{4F4D}\u{7F6E}\u{5DF2}\u{6709}\u{4E66}\u{7B7E}"
                )
            } catch {
                showTransientNotice(title: "\u{4E66}\u{7B7E}\u{4FDD}\u{5B58}\u{5931}\u{8D25}")
            }
        }
    }

    @objc private func showCatalogAndBookmarks() {
        setChromeVisible(false, animated: true)
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let chapters = try await chapterService.chapters(bookID: book.id)
                self.chapters = chapters
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
        listViewController.onBookmarkDeleteRequested = { [weak self] bookmark, completion in
            guard let self else {
                completion(false)
                return
            }
            self.deleteBookmark(bookmark, completion: completion)
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

    private func deleteBookmark(_ bookmark: ReadingBookmark, completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            do {
                try await bookmarkService.deleteBookmark(bookmark)
                completion(true)
            } catch {
                showTransientNotice(title: "\u{4E66}\u{7B7E}\u{5220}\u{9664}\u{5931}\u{8D25}")
                completion(false)
            }
        }
    }

    private func jumpToByteOffset(_ byteOffset: UInt64) {
        stopAutoReading()
        pauseBackgroundWork()
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
        scheduleBackgroundWorkResume(after: 1.5)
    }

    private func handleChromeAction(_ action: ReaderChromeView.Action) {
        switch action {
        case .back:
            navigationController?.popViewController(animated: true)
        case .bookmark:
            addBookmark()
        case .more:
            showMoreMenu()
        case .previousChapter:
            jumpToAdjacentChapter(direction: -1)
        case .nextChapter:
            jumpToAdjacentChapter(direction: 1)
        case .catalog:
            showCatalogAndBookmarks()
        case .settings:
            showReadingSettings()
        case .autoRead:
            startAutoReading()
        case .toggleDarkMode:
            toggleDarkMode()
        }
    }

    private func toggleDarkMode() {
        let enteringDarkMode = traitCollection.userInterfaceStyle != .dark
        preferredInterfaceStyle = enteringDarkMode ? .dark : .light
        overrideUserInterfaceStyle = preferredInterfaceStyle
        activeSettings.theme = enteringDarkMode ? .black : .paper
        readingSettingsStore.save(activeSettings)
        applyTheme(activeSettings.theme)
        refreshVisibleCellsForActiveSettings()
    }

    private func setChromeVisible(_ isVisible: Bool, animated: Bool) {
        isChromeVisible = isVisible
        updateChrome()
        chromeView.setVisible(isVisible, animated: animated)
    }

    private func setAutoReadPanelVisible(_ isVisible: Bool, animated: Bool) {
        isAutoReadPanelVisible = isVisible
        autoReadPanelView.setVisible(isVisible, animated: animated)
    }

    private func startAutoReading() {
        guard !isAutoReading else {
            setAutoReadPanelVisible(true, animated: true)
            return
        }

        updateCurrentPageFromVisiblePage()
        guard currentPage != nil,
              !pages.isEmpty else {
            return
        }

        pauseBackgroundWork()
        setChromeVisible(false, animated: true)
        isAutoReading = true
        setAutoReadPanelVisible(true, animated: true)
        configureCollectionViewForAutoReading()
        alignContentOffsetToCurrentPage()
        scheduleAutoReadTick()
    }

    private func stopAutoReading() {
        guard isAutoReading || autoReadTickTask != nil else {
            return
        }

        autoReadTickTask?.cancel()
        autoReadTickTask = nil
        collectionView.layer.removeAllAnimations()
        updateCurrentPageFromVisiblePage()
        isAutoReading = false
        setAutoReadPanelVisible(false, animated: true)
        configureCollectionViewForActiveSettings()
        alignContentOffsetToCurrentPage()
        updateCurrentPageFromVisiblePage()
        saveCurrentProgress()
        scheduleBackgroundWorkResume(after: 1.5)
    }

    private func configureCollectionViewForAutoReading() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }

        layout.scrollDirection = .vertical
        collectionView.isPagingEnabled = false
        collectionView.alwaysBounceVertical = true
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    private func scheduleAutoReadTick() {
        autoReadTickTask?.cancel()
        autoReadTickTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard let self,
                  isAutoReading else {
                return
            }

            advanceAutoRead(by: 0.25)
            if isAutoReading {
                scheduleAutoReadTick()
            }
        }
    }

    private func advanceAutoRead(by interval: TimeInterval) {
        guard isAutoReading,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              !collectionView.isTracking else {
            return
        }

        let distance = autoReadSpeed * CGFloat(interval)
        guard distance > 0 else {
            return
        }

        let maxOffsetY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let nextOffsetY = min(maxOffsetY, collectionView.contentOffset.y + distance)
        UIView.animate(withDuration: interval, delay: 0, options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction]) {
            self.collectionView.contentOffset = CGPoint(x: self.collectionView.contentOffset.x, y: nextOffsetY)
        } completion: { [weak self] _ in
            self?.updateCurrentPageFromVisiblePage()
        }

        if nextOffsetY >= max(0, maxOffsetY - collectionView.bounds.height * 0.8) {
            loadNextPageIfNeeded()
        }

        if nextOffsetY >= maxOffsetY,
           didReachEndOfBook || (pages.last?.endByteOffset ?? 0) >= book.fileSize {
            stopAutoReading()
        }
    }

    private func alignContentOffsetToCurrentPage() {
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let targetOffset: CGPoint
        if usesVerticalScrolling {
            targetOffset = CGPoint(x: 0, y: CGFloat(currentIndex) * collectionView.bounds.height)
        } else {
            targetOffset = CGPoint(x: CGFloat(currentIndex) * collectionView.bounds.width, y: 0)
        }
        collectionView.setContentOffset(targetOffset, animated: false)
    }

    private func updateChrome() {
        chromeView.configure(
            title: book.title,
            state: currentSessionState(),
            theme: activeSettings.theme
        )
        updateStatusBar()
    }

    private func updateStatusBar() {
        guard let state = currentSessionState() else {
            statusBarView.isHidden = true
            return
        }

        statusBarView.configure(
            state: state,
            settings: activeSettings,
            chapterTitle: nearestChapter(atOrBefore: state.startByteOffset)?.title
        )
    }

    private func currentSessionState() -> ReaderSessionState? {
        guard let currentPage else {
            return nil
        }

        return ReaderSessionState(
            bookID: currentPage.bookID,
            currentPageIndex: currentPage.pageIndex,
            residentPageCount: pages.count,
            startByteOffset: currentPage.startByteOffset,
            endByteOffset: currentPage.endByteOffset,
            fileSize: book.fileSize,
            isLoadingNextPage: isLoadingNextPage,
            didReachEndOfBook: didReachEndOfBook
        )
    }

    private func progressPreviewText(for progress: Float) -> String {
        let clampedProgress = min(1, max(0, Double(progress)))
        let byteOffset = UInt64(clampedProgress * Double(book.fileSize))
        let percentText = NumberFormatter.localizedString(
            from: NSNumber(value: clampedProgress),
            number: .percent
        )
        guard let chapter = nearestChapter(atOrBefore: byteOffset) else {
            return percentText
        }
        return "\(chapter.title) \(percentText)"
    }

    private func jumpToProgress(_ progress: Float) {
        let clampedProgress = min(1, max(0, Double(progress)))
        let byteOffset = min(book.fileSize.lastReadableByteOffset, UInt64(clampedProgress * Double(book.fileSize)))
        jumpToByteOffset(byteOffset)
    }

    private func jumpToAdjacentChapter(direction: Int) {
        updateCurrentPageFromVisiblePage()
        guard let currentPage else {
            return
        }

        if chapters.isEmpty {
            refreshChapters()
            showTransientNotice(title: "\u{76EE}\u{5F55}\u{89E3}\u{6790}\u{4E2D}")
            return
        }

        let targetChapter: ReadingChapter?
        if direction < 0 {
            targetChapter = chapters.last { $0.byteOffset < currentPage.startByteOffset }
        } else {
            targetChapter = chapters.first { $0.byteOffset > currentPage.startByteOffset }
        }

        guard let targetChapter else {
            showTransientNotice(title: direction < 0 ? "\u{5DF2}\u{662F}\u{7B2C}\u{4E00}\u{7AE0}" : "\u{5DF2}\u{662F}\u{6700}\u{540E}\u{4E00}\u{7AE0}")
            return
        }
        jumpToChapter(targetChapter)
    }

    private func nearestChapter(atOrBefore byteOffset: UInt64) -> ReadingChapter? {
        chapters.last { $0.byteOffset <= byteOffset }
    }

    private func refreshChapters() {
        chapterRefreshTask?.cancel()
        chapterRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                chapters = try await chapterService.chapters(bookID: book.id)
            } catch {
                chapters = []
            }
            chapterRefreshTask = nil
            updateChrome()
        }
    }

    private func showMoreMenu() {
        stopAutoReading()
        setChromeVisible(false, animated: true)
        let alert = UIAlertController(
            title: "\u{66F4}\u{591A}",
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(
            UIAlertAction(
                title: "\u{4E66}\u{7C4D}\u{8BE6}\u{60C5}",
                style: .default
            ) { [weak self] _ in
                self?.showBookDetails()
            }
        )
        alert.addAction(
            UIAlertAction(
                title: "\u{5185}\u{5BB9}\u{641C}\u{7D22}",
                style: .default
            ) { [weak self] _ in
                self?.showBookSearch()
            }
        )
        alert.addAction(
            UIAlertAction(
                title: "\u{5185}\u{5BB9}\u{51C0}\u{5316}",
                style: .default
            ) { [weak self] _ in
                self?.showContentFilters()
            }
        )
        alert.addAction(
            UIAlertAction(
                title: "\u{7FFB}\u{9875}\u{533A}\u{57DF}",
                style: .default
            ) { [weak self] _ in
                self?.showTapAreaSettings()
            }
        )
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func showBookDetails() {
        let viewController = BookDetailViewController(
            bookID: book.id,
            detailService: bookDetailService
        )
        viewController.onBookUpdated = { [weak self] updatedBook in
            guard let self else {
                return
            }
            book = updatedBook
            title = updatedBook.title
            updateChrome()
        }
        presentInNavigationSheet(viewController, detents: [.medium(), .large()])
    }

    private func showBookSearch() {
        resumeBackgroundWork()
        let searchViewController = BookSearchViewController(
            book: book,
            searchIndexService: searchIndexService
        )
        searchViewController.onResultSelected = { [weak self] result in
            self?.jumpToByteOffset(result.byteOffset)
        }

        let navigationController = UINavigationController(rootViewController: searchViewController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    private func showContentFilters() {
        let viewController = ContentFilterViewController(
            bookID: book.id,
            service: contentFilterService,
            rules: contentFilterRules
        )
        viewController.onRulesChanged = { [weak self] rules in
            self?.contentFilterRules = rules
            self?.refreshVisibleCellsForActiveSettings()
        }
        presentInNavigationSheet(viewController, detents: [.medium(), .large()])
    }

    private func showTapAreaSettings() {
        let viewController = TapAreaSettingsViewController(settings: tapAreaSettings)
        viewController.onApply = { [weak self] settings in
            guard let self else {
                return
            }
            tapAreaSettings = settings
            do {
                try tapAreaSettingsStore.save(settings, bookID: book.id)
            } catch {
                showTransientNotice(title: "\u{533A}\u{57DF}\u{8BBE}\u{7F6E}\u{4FDD}\u{5B58}\u{5931}\u{8D25}")
            }
        }
        presentInNavigationSheet(viewController, detents: [.medium()])
    }

    private func presentInNavigationSheet(_ viewController: UIViewController, detents: [UISheetPresentationController.Detent]) {
        let navigationController = UINavigationController(rootViewController: viewController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    private func pauseBackgroundWork() {
        backgroundWorkResumeTask?.cancel()
        backgroundWorkResumeTask = nil
        chapterService.pauseParsing(bookID: book.id)
        searchIndexService.pauseIndexing(bookID: book.id)
    }

    private func scheduleBackgroundWorkResume(after delay: TimeInterval) {
        backgroundWorkResumeTask?.cancel()
        backgroundWorkResumeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            guard let self,
                  !isAutoReading,
                  !collectionView.isDragging,
                  !collectionView.isDecelerating,
                  !collectionView.isTracking else {
                return
            }
            resumeBackgroundWork()
        }
    }

    private func resumeBackgroundWork() {
        chapterService.resumeParsing(bookID: book.id)
        searchIndexService.resumeIndexing(bookID: book.id, startingAt: currentPage?.startByteOffset ?? 0)
    }

    private func refreshVisibleCellsForActiveSettings() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard pages.indices.contains(indexPath.item),
                  let cell = collectionView.cellForItem(at: indexPath) as? ReaderPageCell else {
                continue
            }
            cell.configure(page: pages[indexPath.item], settings: activeSettings, filterRules: contentFilterRules)
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
        loadTapAreaSettings()
        refreshContentFilterRules()
        applyReaderPreferences()
        applyTheme(activeSettings.theme)
        openPage(preferredByteOffset: nil)
    }

    private func loadTapAreaSettings() {
        do {
            tapAreaSettings = try tapAreaSettingsStore.load(bookID: book.id)
        } catch {
            tapAreaSettings = .standard
        }
    }

    private func refreshContentFilterRules() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                contentFilterRules = try await contentFilterService.rules(bookID: book.id)
                refreshVisibleCellsForActiveSettings()
            } catch {
                contentFilterRules = []
            }
        }
    }

    private func openPage(preferredByteOffset: UInt64?) {
        openingTask?.cancel()
        previousPageTask?.cancel()
        nextPageTask?.cancel()
        previousPageTask = nil
        nextPageTask = nil
        isLoadingNextPage = false
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
                loadPreviousPageIfNeeded()
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
        searchIndexService.scheduleIndexing(bookID: book.id, startingAt: page.startByteOffset)
        refreshChapters()
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

    private func prependPage(_ page: ReaderPage) {
        guard !pages.contains(where: { $0.startByteOffset == page.startByteOffset }) else {
            return
        }

        pages.insert(page, at: 0)
        let pageLength = usesVerticalScrolling
            ? collectionView.bounds.height
            : collectionView.bounds.width
        trimResidentPagesAfterPrepending()
        applyPagesSnapshot()
        if pageLength > 0 {
            let adjustedOffset: CGPoint
            if usesVerticalScrolling {
                adjustedOffset = CGPoint(
                    x: collectionView.contentOffset.x,
                    y: collectionView.contentOffset.y + pageLength
                )
            } else {
                adjustedOffset = CGPoint(
                    x: collectionView.contentOffset.x + pageLength,
                    y: collectionView.contentOffset.y
                )
            }
            collectionView.setContentOffset(adjustedOffset, animated: false)
        }
        refreshVisibleCellsForActiveSettings()
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
    }

    private func applyPagesSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ReaderPage>()
        snapshot.appendSections([.main])
        snapshot.appendItems(pages, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
        updateStatusBar()
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

    private func loadPreviousPageIfNeeded() {
        guard previousPageTask == nil,
              let firstPage = pages.first,
              firstPage.startByteOffset > 0 else {
            return
        }

        let request = ReaderPreviousPageRequest(
            bookID: book.id,
            endByteOffset: firstPage.startByteOffset,
            pageIndex: max(0, firstPage.pageIndex - 1),
            layout: activeSettings.layout
        )
        let generation = pagingGeneration

        previousPageTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let previousPage = try await pagingService.previousPage(request)
                guard pagingGeneration == generation else {
                    return
                }
                previousPageTask = nil
                guard let previousPage else {
                    return
                }
                prependPage(previousPage)
            } catch {
                guard pagingGeneration == generation else {
                    return
                }
                previousPageTask = nil
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
        guard collectionView.bounds.width > 1,
              collectionView.bounds.height > 1 else {
            return
        }

        let visibleCenter = CGPoint(
            x: collectionView.contentOffset.x + collectionView.bounds.midX,
            y: collectionView.contentOffset.y + collectionView.bounds.midY
        )
        guard let indexPath = collectionView.indexPathForItem(at: visibleCenter),
              pages.indices.contains(indexPath.item) else {
            return
        }

        let visiblePage = pages[indexPath.item]
        guard currentPage != visiblePage || isLoadingNextPage != (nextPageTask != nil) else {
            return
        }

        currentPage = visiblePage
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

    private func trimResidentPagesAfterPrepending() {
        guard pages.count > maximumResidentPages,
              let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let overflow = pages.count - maximumResidentPages
        let removableAfterCurrent = max(0, pages.count - currentIndex - 4)
        let removeCount = min(overflow, removableAfterCurrent)
        guard removeCount > 0 else {
            return
        }

        pages.removeLast(removeCount)
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
        let pageLength = usesVerticalScrolling
            ? collectionView.bounds.height
            : collectionView.bounds.width
        guard pageLength > 0 else {
            return
        }

        let distance = CGFloat(removePrefixCount) * pageLength
        let adjustedOffset: CGPoint
        if usesVerticalScrolling {
            adjustedOffset = CGPoint(
                x: collectionView.contentOffset.x,
                y: max(0, collectionView.contentOffset.y - distance)
            )
        } else {
            adjustedOffset = CGPoint(
                x: max(0, collectionView.contentOffset.x - distance),
                y: collectionView.contentOffset.y
            )
        }
        collectionView.setContentOffset(adjustedOffset, animated: false)
    }

    private func updateSessionState(isLoadingNextPage: Bool) {
        self.isLoadingNextPage = isLoadingNextPage
        updateChrome()
    }

    @objc private func handleReaderTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        let location = gesture.location(in: collectionView)
        updateCurrentPageFromVisiblePage()

        if isAutoReading {
            let centralHorizontalRange = collectionView.bounds.width * 0.25...collectionView.bounds.width * 0.75
            let centralVerticalRange = collectionView.bounds.height * 0.20...collectionView.bounds.height * 0.80
            guard centralHorizontalRange.contains(location.x),
                  centralVerticalRange.contains(location.y) else {
                return
            }
            setAutoReadPanelVisible(!isAutoReadPanelVisible, animated: true)
            return
        }

        switch tapAreaSettings.action(for: tapAreaIndex(for: location)) {
        case .toggleMenu:
            setChromeVisible(!isChromeVisible, animated: true)
        case .previousPage:
            guard !isChromeVisible else {
                return
            }
            pageBackwardFromTap()
        case .nextPage:
            guard !isChromeVisible else {
                return
            }
            pageForwardFromTap()
        }
    }

    private func tapAreaIndex(for location: CGPoint) -> Int {
        let width = max(1, collectionView.bounds.width)
        let height = max(1, collectionView.bounds.height)
        let column = min(2, max(0, Int((location.x / width) * 3)))
        let row = min(2, max(0, Int((location.y / height) * 3)))
        return row * 3 + column
    }

    private func pageForwardFromTap() {
        pauseBackgroundWork()
        scheduleBackgroundWorkResume(after: 1.2)
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let nextIndex = currentIndex + 1
        if pages.indices.contains(nextIndex) {
            scrollToPage(at: nextIndex, animated: true)
        } else {
            loadNextPageIfNeeded()
        }
    }

    private func pageBackwardFromTap() {
        pauseBackgroundWork()
        scheduleBackgroundWorkResume(after: 1.2)
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let previousIndex = currentIndex - 1
        if pages.indices.contains(previousIndex) {
            scrollToPage(at: previousIndex, animated: true)
        } else {
            loadPreviousPageIfNeeded()
        }
    }

    private func scrollToPage(at index: Int, animated: Bool) {
        guard pages.indices.contains(index) else {
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        let position: UICollectionView.ScrollPosition = usesVerticalScrolling ? .centeredVertically : .centeredHorizontally
        collectionView.scrollToItem(at: indexPath, at: position, animated: animated)
        currentPage = pages[index]
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
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
        if indexPath.item <= 1 {
            loadPreviousPageIfNeeded()
        }
        if indexPath.item >= pages.count - 2 {
            loadNextPageIfNeeded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentPageFromVisiblePage()
        loadPreviousPageIfNeeded()
        loadNextPageIfNeeded()
        scheduleBackgroundWorkResume(after: 1.5)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else {
            return
        }

        updateCurrentPageFromVisiblePage()
        loadPreviousPageIfNeeded()
        loadNextPageIfNeeded()
        scheduleBackgroundWorkResume(after: 1.5)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pauseBackgroundWork()
        if isAutoReading {
            stopAutoReading()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }
}

private extension UInt64 {
    var lastReadableByteOffset: UInt64 {
        self > 0 ? self - 1 : 0
    }
}
