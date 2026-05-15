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
    private let autoReadPanelView = AutoReadSpeedPanelView()
    private var moreMenuView: UIView?

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
    private var bookmarkStateTask: Task<Void, Never>?
    private var backgroundWorkResumeTask: Task<Void, Never>?
    private var bookmarkStateByteOffset: UInt64?
    private var isCurrentPageBookmarked = false
    private var shouldScrollToPreviousPageAfterLoad = false
    private var shouldScrollToNextPageAfterLoad = false
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
    private weak var previousInteractivePopGestureDelegate: UIGestureRecognizerDelegate?
    private var previousInteractivePopGestureWasEnabled = true
    private var didCaptureInteractivePopGestureState = false
    private let maximumResidentPages = 12
    private var lastPaginationMetrics: ReaderViewportMetrics?
    private var usesVerticalScrolling: Bool {
        isAutoReading || activeSettings.pageTurnMode == .verticalScroll
    }

    private var pageRenderingSettings: ReadingSettings {
        var settings = activeSettings
        settings.layout = effectiveReadingLayout(from: activeSettings.layout)
        return settings
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
        configureAutoReadPanel()
        configureChrome()
        configureGestures()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveCurrentProgressForBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshVisibleReaderWidgets),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshVisibleReaderWidgets),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        applyReaderPreferences()
        scheduleBackgroundWorkResume(after: 1.5)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureSwipeBackGesture()
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
        reflowForViewportChangeIfNeeded()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        reflowForViewportChangeIfNeeded()
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
        restoreSwipeBackGestureAfterTransitionIfNeeded()
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
        bookmarkStateTask?.cancel()
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
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
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
            cell.configure(
                page: page,
                settings: pageRenderingSettings,
                filterRules: contentFilterRules,
                statusConfiguration: statusConfiguration(for: page)
            )
            return cell
        }
    }

    private func configureAutoReadPanel() {
        view.addSubview(autoReadPanelView)
        NSLayoutConstraint.activate([
            autoReadPanelView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            autoReadPanelView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            autoReadPanelView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
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
            self?.dismissMoreMenu(animated: true)
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
        autoReadPanelView.configure(speed: autoReadSpeed, theme: theme)
        configureChromeView()
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

    @objc private func refreshVisibleReaderWidgets() {
        refreshVisibleCellsForActiveSettings()
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
        configureSwipeBackGesture()
        configureCollectionViewForActiveSettings()
        refreshVisibleCellsForActiveSettings()
    }

    private func configureSwipeBackGesture() {
        guard let navigationController,
              let gesture = navigationController.interactivePopGestureRecognizer else {
            return
        }

        if !didCaptureInteractivePopGestureState {
            previousInteractivePopGestureDelegate = gesture.delegate
            previousInteractivePopGestureWasEnabled = gesture.isEnabled
            didCaptureInteractivePopGestureState = true
        }

        let shouldEnable = activeSettings.allowsSwipeBack && navigationController.viewControllers.count > 1
        if shouldEnable {
            gesture.delegate = self
            collectionView.panGestureRecognizer.require(toFail: gesture)
        } else {
            gesture.delegate = previousInteractivePopGestureDelegate
        }
        gesture.isEnabled = shouldEnable
    }

    private func restoreSwipeBackGestureAfterTransitionIfNeeded() {
        guard didCaptureInteractivePopGestureState else {
            return
        }

        guard let transitionCoordinator else {
            restoreSwipeBackGesture()
            return
        }

        transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self else {
                return
            }
            if context.isCancelled {
                configureSwipeBackGesture()
            } else {
                restoreSwipeBackGesture()
            }
        }
    }

    private func restoreSwipeBackGesture() {
        guard didCaptureInteractivePopGestureState,
              let gesture = navigationController?.interactivePopGestureRecognizer else {
            return
        }

        gesture.delegate = previousInteractivePopGestureDelegate
        gesture.isEnabled = previousInteractivePopGestureWasEnabled
        previousInteractivePopGestureDelegate = nil
        didCaptureInteractivePopGestureState = false
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

    private func effectiveReadingLayout(from layout: ReadingLayout) -> ReadingLayout {
        var adjustedLayout = layout
        if collectionView.bounds.width > 1,
           collectionView.bounds.height > 1 {
            adjustedLayout.viewportSize = collectionView.bounds.size
        }

        let safeAreaInsets = view.safeAreaInsets
        let edgePadding: CGFloat = 12
        let statusPadding: CGFloat = 34
        let safeTop = safeAreaInsets.top > 0 ? safeAreaInsets.top + edgePadding : 0
        let safeLeft = safeAreaInsets.left > 0 ? safeAreaInsets.left + edgePadding : 0
        let safeBottom = safeAreaInsets.bottom > 0 ? safeAreaInsets.bottom + edgePadding : 0
        let safeRight = safeAreaInsets.right > 0 ? safeAreaInsets.right + edgePadding : 0
        adjustedLayout.contentInsets.top = max(adjustedLayout.contentInsets.top, safeTop)
        adjustedLayout.contentInsets.left = max(adjustedLayout.contentInsets.left, safeLeft)
        adjustedLayout.contentInsets.bottom = max(adjustedLayout.contentInsets.bottom, safeBottom)
        adjustedLayout.contentInsets.right = max(adjustedLayout.contentInsets.right, safeRight)

        let reservedTop = max(statusPadding, safeAreaInsets.top + statusPadding)
        let reservedBottom = max(statusPadding, safeAreaInsets.bottom + 24)
        let reservesBottom = activeSettings.statusBarItems.contains(.batteryPercent)
            || activeSettings.statusBarItems.contains(.battery)
            || activeSettings.statusBarItems.contains(.time)
            || activeSettings.statusBarItems.contains(.chapterPageProgress)
            || activeSettings.statusBarItems.contains(.bookProgress)

        if activeSettings.statusBarItems.contains(.chapterTitle) {
            adjustedLayout.contentInsets.top = max(adjustedLayout.contentInsets.top, reservedTop)
        }
        if reservesBottom {
            adjustedLayout.contentInsets.bottom = max(adjustedLayout.contentInsets.bottom, reservedBottom)
        }
        return adjustedLayout
    }

    @objc private func addBookmark() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage else {
            return
        }
        let bookmarkPage = currentPage
        let shouldRemoveBookmark = isCurrentPageBookmarked

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                if shouldRemoveBookmark {
                    if let bookmark = try await bookmarkService.bookmark(
                        bookID: book.id,
                        byteOffset: bookmarkPage.startByteOffset
                    ) {
                        try await bookmarkService.deleteBookmark(bookmark)
                    }
                    if self.currentPage?.startByteOffset == bookmarkPage.startByteOffset {
                        bookmarkStateTask?.cancel()
                        bookmarkStateTask = nil
                        isCurrentPageBookmarked = false
                        bookmarkStateByteOffset = bookmarkPage.startByteOffset
                        chromeView.setBookmarkActive(false)
                    }
                    return
                }

                _ = try await bookmarkService.addBookmark(bookID: book.id, page: bookmarkPage)
                if self.currentPage?.startByteOffset == bookmarkPage.startByteOffset {
                    bookmarkStateTask?.cancel()
                    bookmarkStateTask = nil
                    isCurrentPageBookmarked = true
                    bookmarkStateByteOffset = bookmarkPage.startByteOffset
                    chromeView.setBookmarkActive(true)
                }
            } catch {
                refreshBookmarkState(force: true)
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

        if let navigationController {
            navigationController.setNavigationBarHidden(false, animated: true)
            navigationController.pushViewController(listViewController, animated: true)
        } else {
            let navigationController = UINavigationController(rootViewController: listViewController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        }
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
                if currentPage?.startByteOffset == bookmark.byteOffset {
                    refreshBookmarkState(force: true)
                }
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
        if !isVisible {
            dismissMoreMenu(animated: animated)
        }
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
        configureChromeView()
        chromeView.setBookmarkActive(isCurrentPageBookmarked)
    }

    private func configureChromeView() {
        chromeView.configure(
            title: book.title,
            state: currentSessionState(),
            theme: activeSettings.theme,
            progressValue: currentChapterProgressValue(),
            progressText: currentChapterProgressText()
        )
    }

    private func refreshBookmarkState(force: Bool = false) {
        guard let currentPage else {
            resetBookmarkState()
            return
        }

        let byteOffset = currentPage.startByteOffset
        guard force || bookmarkStateByteOffset != byteOffset else {
            chromeView.setBookmarkActive(isCurrentPageBookmarked)
            return
        }

        bookmarkStateTask?.cancel()
        bookmarkStateByteOffset = byteOffset
        isCurrentPageBookmarked = false
        chromeView.setBookmarkActive(false)

        bookmarkStateTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let bookmark = try await bookmarkService.bookmark(bookID: book.id, byteOffset: byteOffset)
                guard !Task.isCancelled,
                      self.currentPage?.startByteOffset == byteOffset else {
                    return
                }
                isCurrentPageBookmarked = bookmark != nil
                chromeView.setBookmarkActive(bookmark != nil)
            } catch {
                guard self.currentPage?.startByteOffset == byteOffset else {
                    return
                }
                isCurrentPageBookmarked = false
                chromeView.setBookmarkActive(false)
            }
            bookmarkStateTask = nil
        }
    }

    private func resetBookmarkState() {
        bookmarkStateTask?.cancel()
        bookmarkStateTask = nil
        bookmarkStateByteOffset = nil
        isCurrentPageBookmarked = false
        chromeView.setBookmarkActive(false)
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

    private func currentChapterProgressValue() -> Float? {
        guard let currentPage else {
            return nil
        }
        return chapterRange(containing: currentPage.startByteOffset)
            .progress(for: currentPage.startByteOffset)
    }

    private func currentChapterProgressText() -> String? {
        guard let currentPage else {
            return nil
        }
        let range = chapterRange(containing: currentPage.startByteOffset)
        return chapterProgressText(
            title: range.title,
            progress: range.progress(for: currentPage.startByteOffset)
        )
    }

    private func progressPreviewText(for progress: Float) -> String {
        let clampedProgress = min(1, max(0, Double(progress)))
        let range = chapterRangeForCurrentPage()
        return chapterProgressText(title: range.title, progress: Float(clampedProgress))
    }

    private func jumpToProgress(_ progress: Float) {
        let clampedProgress = min(1, max(0, Double(progress)))
        let range = chapterRangeForCurrentPage()
        let byteOffset = range.byteOffset(for: clampedProgress)
        jumpToByteOffset(byteOffset)
    }

    private func chapterProgressText(title: String?, progress: Float) -> String {
        let clampedProgress = min(Float(1), max(Float(0), progress))
        let percentText = NumberFormatter.localizedString(
            from: NSNumber(value: clampedProgress),
            number: .percent
        )
        return "\(title ?? "\u{672C}\u{7AE0}") \(percentText)"
    }

    private func chapterRangeForCurrentPage() -> ChapterByteRange {
        updateCurrentPageFromVisiblePage()
        return chapterRange(containing: currentPage?.startByteOffset ?? 0)
    }

    private func chapterRange(containing byteOffset: UInt64) -> ChapterByteRange {
        let fileEnd = max(UInt64(1), book.fileSize)
        let readableByteOffset = min(byteOffset, fileEnd - 1)
        guard !chapters.isEmpty else {
            return ChapterByteRange(title: nil, startByteOffset: 0, endByteOffset: fileEnd)
        }

        if let index = chapters.lastIndex(where: { $0.byteOffset <= readableByteOffset }) {
            let chapter = chapters[index]
            let rawEndByteOffset = chapters.indices.contains(index + 1)
                ? chapters[index + 1].byteOffset
                : fileEnd
            return ChapterByteRange(
                title: chapter.title,
                startByteOffset: min(chapter.byteOffset, fileEnd - 1),
                endByteOffset: min(fileEnd, rawEndByteOffset)
            )
        }

        let firstChapterStart = min(chapters[0].byteOffset, fileEnd)
        return ChapterByteRange(
            title: nil,
            startByteOffset: 0,
            endByteOffset: max(UInt64(1), firstChapterStart)
        )
    }

    private func chapterUpperBoundForPage(startingAt byteOffset: UInt64) -> UInt64? {
        guard !chapters.isEmpty else {
            return nil
        }
        return chapterRange(containing: byteOffset).endByteOffset
    }

    private func chapterLowerBoundForPreviousPage(endingAt byteOffset: UInt64) -> UInt64? {
        guard !chapters.isEmpty,
              byteOffset > 0 else {
            return nil
        }

        if let exactChapterIndex = chapters.firstIndex(where: { $0.byteOffset == byteOffset }) {
            guard exactChapterIndex > 0 else {
                return 0
            }
            return chapters[exactChapterIndex - 1].byteOffset
        }

        return chapterRange(containing: byteOffset - 1).startByteOffset
    }

    private func statusConfiguration(for page: ReaderPage) -> ReaderStatusBarView.Configuration? {
        guard !activeSettings.statusBarItems.isEmpty else {
            return nil
        }

        let state = ReaderSessionState(
            bookID: page.bookID,
            currentPageIndex: page.pageIndex,
            residentPageCount: pages.count,
            startByteOffset: page.startByteOffset,
            endByteOffset: page.endByteOffset,
            fileSize: book.fileSize,
            isLoadingNextPage: isLoadingNextPage,
            didReachEndOfBook: didReachEndOfBook
        )
        let chapter = nearestChapter(atOrBefore: page.startByteOffset)
        return ReaderStatusBarView.Configuration(
            state: state,
            settings: activeSettings,
            chapterTitle: statusChapterTitle(for: page, chapter: chapter),
            chapterProgress: chapterProgress(for: page, state: state, chapter: chapter)
        )
    }

    private func statusChapterTitle(for page: ReaderPage, chapter: ReadingChapter?) -> String? {
        guard activeSettings.statusBarItems.contains(.chapterTitle) else {
            return nil
        }

        return ReaderTextStyler.startsWithChapterTitle(page.text)
            ? book.title
            : (chapter?.title ?? book.title)
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

    private func chapterProgress(
        for page: ReaderPage,
        state: ReaderSessionState,
        chapter: ReadingChapter?
    ) -> ReaderStatusBarView.ChapterProgress {
        guard let chapter else {
            return ReaderStatusBarView.ChapterProgress(pageIndex: state.currentPageIndex, pageCount: nil)
        }

        let nextChapter = chapters.first { $0.byteOffset > chapter.byteOffset }
        let chapterEndByteOffset = min(book.fileSize, nextChapter?.byteOffset ?? book.fileSize)
        guard chapterEndByteOffset > chapter.byteOffset else {
            return ReaderStatusBarView.ChapterProgress(pageIndex: state.currentPageIndex, pageCount: nil)
        }

        let pageByteCount = max(UInt64(1), page.endByteOffset - page.startByteOffset)
        let chapterByteCount = max(UInt64(1), chapterEndByteOffset - chapter.byteOffset)
        let completedByteCount = page.startByteOffset > chapter.byteOffset
            ? page.startByteOffset - chapter.byteOffset
            : 0
        let pageCount = max(1, Int(ceil(Double(chapterByteCount) / Double(pageByteCount))))
        let pageIndex = min(pageCount - 1, Int(Double(completedByteCount) / Double(pageByteCount)))
        return ReaderStatusBarView.ChapterProgress(
            pageIndex: max(0, pageIndex),
            pageCount: pageCount
        )
    }

    private func refreshChapters() {
        chapterRefreshTask?.cancel()
        chapterRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            var shouldReflowForChapterBoundaries = false
            do {
                let loadedChapters = try await chapterService.chapters(bookID: book.id)
                shouldReflowForChapterBoundaries = !loadedChapters.isEmpty
                    && loadedChapters != chapters
                    && currentPage != nil
                chapters = loadedChapters
            } catch {
                chapters = []
            }
            chapterRefreshTask = nil
            updateChrome()
            if shouldReflowForChapterBoundaries {
                reflowCurrentPageForChapterBoundaries()
            }
        }
    }

    private func reflowCurrentPageForChapterBoundaries() {
        guard !isAutoReading else {
            return
        }

        updateCurrentPageFromVisiblePage()
        let preferredByteOffset = currentPage?.startByteOffset
        pagingService.removeCachedPages()
        openPage(preferredByteOffset: preferredByteOffset)
    }

    private func showMoreMenu() {
        guard !isAutoReading else {
            setAutoReadPanelVisible(true, animated: true)
            return
        }

        if moreMenuView != nil {
            dismissMoreMenu(animated: true)
            return
        }

        view.layoutIfNeeded()
        let rowHeight: CGFloat = 44
        let menuWidth: CGFloat = 156
        let menuTitles = [
            "\u{4E66}\u{7C4D}\u{8BE6}\u{60C5}",
            "\u{5185}\u{5BB9}\u{641C}\u{7D22}",
            "\u{5185}\u{5BB9}\u{51C0}\u{5316}",
            "\u{7FFB}\u{9875}\u{533A}\u{57DF}"
        ]
        let separatorHeight = 1 / UIScreen.main.scale
        let menuHeight = CGFloat(menuTitles.count) * rowHeight
            + CGFloat(max(0, menuTitles.count - 1)) * separatorHeight
        let anchorFrame = chromeView.moreButtonFrame(in: view)
        let safeFrame = view.safeAreaLayoutGuide.layoutFrame
        let trailingX = min(anchorFrame.maxX, safeFrame.maxX - 12)
        let originX = max(safeFrame.minX + 12, trailingX - menuWidth)
        let originY = min(anchorFrame.maxY + 6, safeFrame.maxY - menuHeight - 12)

        let container = UIView(
            frame: CGRect(
                x: originX,
                y: max(safeFrame.minY + 8, originY),
                width: menuWidth,
                height: menuHeight
            )
        )
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: -4)
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.24
        container.layer.shadowRadius = 12
        container.layer.shadowOffset = CGSize(width: 0, height: 6)
        container.accessibilityViewIsModal = true

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = true
        container.addSubview(contentView)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        contentView.addSubview(stackView)

        let actions: [() -> Void] = [
            { [weak self] in self?.showBookDetails() },
            { [weak self] in self?.showBookSearch() },
            { [weak self] in self?.showContentFilters() },
            { [weak self] in self?.showTapAreaSettings() }
        ]
        for index in menuTitles.indices {
            addMoreMenuButton(
                title: menuTitles[index],
                rowHeight: rowHeight,
                to: stackView,
                action: actions[index]
            )
            if index < menuTitles.index(before: menuTitles.endIndex) {
                let separator = UIView()
                separator.backgroundColor = UIColor.white.withAlphaComponent(0.10)
                stackView.addArrangedSubview(separator)
                separator.heightAnchor.constraint(equalToConstant: separatorHeight).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        view.addSubview(container)
        moreMenuView = container
        UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            container.alpha = 1
            container.transform = .identity
        }
    }

    private func addMoreMenuButton(
        title: String,
        rowHeight: CGFloat,
        to stackView: UIStackView,
        action: @escaping () -> Void
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        configuration.baseForegroundColor = .white

        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addAction(
            UIAction { [weak self] _ in
                self?.dismissMoreMenu(animated: true)
                self?.setChromeVisible(false, animated: true)
                action()
            },
            for: .touchUpInside
        )
        stackView.addArrangedSubview(button)
        button.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
    }

    private func dismissMoreMenu(animated: Bool) {
        guard let menuView = moreMenuView else {
            return
        }

        moreMenuView = nil
        let removeMenu = {
            menuView.removeFromSuperview()
        }

        guard animated else {
            removeMenu()
            return
        }

        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            menuView.alpha = 0
            menuView.transform = CGAffineTransform(translationX: 0, y: -4)
        } completion: { _ in
            removeMenu()
        }
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
        viewController.onChange = { [weak self] settings in
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

        if let navigationController {
            navigationController.setNavigationBarHidden(false, animated: true)
            navigationController.pushViewController(viewController, animated: true)
        } else {
            let navigationController = UINavigationController(rootViewController: viewController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        }
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
            let page = pages[indexPath.item]
            cell.configure(
                page: page,
                settings: pageRenderingSettings,
                filterRules: contentFilterRules,
                statusConfiguration: statusConfiguration(for: page)
            )
        }
    }

    private func openFirstPageIfNeeded() {
        guard !didStartOpening,
              collectionView.bounds.width > 1,
              collectionView.bounds.height > 1 else {
            return
        }

        didStartOpening = true
        lastPaginationMetrics = currentViewportMetrics()
        activeSettings = readingSettingsStore.load().normalized(viewportSize: collectionView.bounds.size)
        loadTapAreaSettings()
        refreshContentFilterRules()
        applyReaderPreferences()
        applyTheme(activeSettings.theme)
        openPage(preferredByteOffset: nil)
    }

    private func reflowForViewportChangeIfNeeded() {
        guard didStartOpening,
              let metrics = currentViewportMetrics() else {
            return
        }

        guard let previousMetrics = lastPaginationMetrics else {
            lastPaginationMetrics = metrics
            return
        }

        guard previousMetrics != metrics else {
            return
        }

        lastPaginationMetrics = metrics
        updateCurrentPageFromVisiblePage()
        let preferredByteOffset = currentPage?.startByteOffset
        activeSettings = activeSettings.normalized(viewportSize: collectionView.bounds.size)
        pagingService.removeCachedPages()
        openPage(preferredByteOffset: preferredByteOffset)
    }

    private func currentViewportMetrics() -> ReaderViewportMetrics? {
        guard collectionView.bounds.width > 1,
              collectionView.bounds.height > 1 else {
            return nil
        }

        return ReaderViewportMetrics(
            size: collectionView.bounds.size,
            safeAreaInsets: view.safeAreaInsets,
            scale: UIScreen.main.scale
        )
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
        shouldScrollToPreviousPageAfterLoad = false
        shouldScrollToNextPageAfterLoad = false
        isLoadingNextPage = false
        pages = []
        currentPage = nil
        resetBookmarkState()
        applyPagesSnapshot()
        didReachEndOfBook = false
        pagingGeneration += 1
        let generation = pagingGeneration
        let requestStartByteOffset = preferredByteOffset ?? currentPage?.startByteOffset ?? 0
        let request = ReaderOpeningRequest(
            bookID: book.id,
            viewportSize: collectionView.bounds.size,
            layout: effectiveReadingLayout(from: activeSettings.layout),
            preferredByteOffset: preferredByteOffset,
            upperBoundByteOffset: chapterUpperBoundForPage(startingAt: requestStartByteOffset)
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

    @discardableResult
    private func appendPage(_ page: ReaderPage) -> Int? {
        if let existingIndex = pages.firstIndex(where: { $0.startByteOffset == page.startByteOffset }) {
            return existingIndex
        }
        pages.append(page)
        let removedPrefixCount = trimResidentPagesIfNeeded()
        applyPagesSnapshot()
        adjustContentOffsetAfterRemovingPrefix(removedPrefixCount)
        refreshVisibleCellsForActiveSettings()
        updateSessionState(isLoadingNextPage: false)
        return pages.firstIndex(of: page)
    }

    @discardableResult
    private func prependPage(_ page: ReaderPage) -> Int? {
        if let existingIndex = pages.firstIndex(where: { $0.startByteOffset == page.startByteOffset }) {
            return existingIndex
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
        return pages.firstIndex(of: page)
    }

    private func applyPagesSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ReaderPage>()
        snapshot.appendSections([.main])
        snapshot.appendItems(pages, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func loadNextPageIfNeeded(scrollAfterLoading: Bool = false) {
        if scrollAfterLoading {
            shouldScrollToNextPageAfterLoad = true
        }
        guard !didReachEndOfBook,
              let lastPage = pages.last,
              lastPage.endByteOffset < book.fileSize else {
            shouldScrollToNextPageAfterLoad = false
            return
        }
        guard nextPageTask == nil else {
            return
        }

        let request = ReaderPageRequest(
            bookID: book.id,
            startByteOffset: lastPage.endByteOffset,
            pageIndex: lastPage.pageIndex + 1,
            layout: effectiveReadingLayout(from: activeSettings.layout),
            upperBoundByteOffset: chapterUpperBoundForPage(startingAt: lastPage.endByteOffset)
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
                    shouldScrollToNextPageAfterLoad = false
                    updateSessionState(isLoadingNextPage: false)
                    return
                }
                let shouldScroll = shouldScrollToNextPageAfterLoad
                shouldScrollToNextPageAfterLoad = false
                if let index = appendPage(nextPage),
                   shouldScroll {
                    scrollToPage(at: index, animated: false)
                }
            } catch {
                guard pagingGeneration == generation else {
                    return
                }
                nextPageTask = nil
                shouldScrollToNextPageAfterLoad = false
                updateSessionState(isLoadingNextPage: false)
            }
        }
    }

    private func loadPreviousPageIfNeeded(scrollAfterLoading: Bool = false) {
        if scrollAfterLoading {
            shouldScrollToPreviousPageAfterLoad = true
        }
        guard let firstPage = pages.first,
              firstPage.startByteOffset > 0 else {
            shouldScrollToPreviousPageAfterLoad = false
            return
        }
        guard previousPageTask == nil else {
            return
        }

        let request = ReaderPreviousPageRequest(
            bookID: book.id,
            endByteOffset: firstPage.startByteOffset,
            pageIndex: max(0, firstPage.pageIndex - 1),
            layout: effectiveReadingLayout(from: activeSettings.layout),
            lowerBoundByteOffset: chapterLowerBoundForPreviousPage(endingAt: firstPage.startByteOffset)
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
                    shouldScrollToPreviousPageAfterLoad = false
                    return
                }
                let shouldScroll = shouldScrollToPreviousPageAfterLoad
                shouldScrollToPreviousPageAfterLoad = false
                if let index = prependPage(previousPage),
                   shouldScroll {
                    scrollToPage(at: index, animated: false)
                }
            } catch {
                guard pagingGeneration == generation else {
                    return
                }
                previousPageTask = nil
                shouldScrollToPreviousPageAfterLoad = false
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

        guard let visibleIndex = visiblePageIndex() else {
            return
        }

        let visiblePage = pages[visibleIndex]
        guard currentPage != visiblePage || isLoadingNextPage != (nextPageTask != nil) else {
            return
        }

        currentPage = visiblePage
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
    }

    private func visiblePageIndex() -> Int? {
        guard !pages.isEmpty else {
            return nil
        }

        let pageLength = usesVerticalScrolling
            ? collectionView.bounds.height
            : collectionView.bounds.width
        guard pageLength > 1 else {
            return nil
        }

        let rawOffset = usesVerticalScrolling
            ? collectionView.contentOffset.y / pageLength
            : collectionView.contentOffset.x / pageLength
        let roundedIndex = Int(round(rawOffset))
        return min(max(roundedIndex, 0), pages.count - 1)
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
        refreshBookmarkState()
    }

    @objc private func handleReaderTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        let location = viewportLocation(forViewLocation: gesture.location(in: view))
        updateCurrentPageFromVisiblePage()

        if moreMenuView != nil {
            dismissMoreMenu(animated: true)
            return
        }

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

    private func viewportLocation(forViewLocation viewLocation: CGPoint) -> CGPoint {
        // Tap actions use the visible viewport, not the collection view's content
        // coordinates, so the same 3x3 map works after horizontal or vertical scrolling.
        CGPoint(
            x: viewLocation.x - collectionView.frame.minX,
            y: viewLocation.y - collectionView.frame.minY
        )
    }

    private func pageForwardFromTap() {
        guard snapToNearestPageIfNeeded(),
              openingTask == nil else {
            return
        }
        pauseBackgroundWork()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let nextIndex = currentIndex + 1
        if pages.indices.contains(nextIndex) {
            scrollToPage(at: nextIndex, animated: false)
        } else {
            loadNextPageIfNeeded(scrollAfterLoading: true)
        }
    }

    private func pageBackwardFromTap() {
        guard snapToNearestPageIfNeeded(),
              openingTask == nil else {
            return
        }
        pauseBackgroundWork()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }

        let previousIndex = currentIndex - 1
        if pages.indices.contains(previousIndex) {
            scrollToPage(at: previousIndex, animated: false)
        } else {
            loadPreviousPageIfNeeded(scrollAfterLoading: true)
        }
    }

    @discardableResult
    private func snapToNearestPageIfNeeded() -> Bool {
        guard let visibleIndex = visiblePageIndex() else {
            return false
        }

        let targetOffset = contentOffset(forPageAt: visibleIndex)
        let distance = usesVerticalScrolling
            ? abs(collectionView.contentOffset.y - targetOffset.y)
            : abs(collectionView.contentOffset.x - targetOffset.x)
        if distance > 0.5 {
            collectionView.setContentOffset(targetOffset, animated: false)
        }

        currentPage = pages[visibleIndex]
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
        return true
    }

    private func contentOffset(forPageAt index: Int) -> CGPoint {
        if usesVerticalScrolling {
            return CGPoint(x: 0, y: CGFloat(index) * collectionView.bounds.height)
        }

        return CGPoint(x: CGFloat(index) * collectionView.bounds.width, y: 0)
    }

    private func scrollToPage(at index: Int, animated: Bool) {
        guard pages.indices.contains(index) else {
            return
        }

        collectionView.layoutIfNeeded()
        let targetOffset = contentOffset(forPageAt: index)
        let distance = usesVerticalScrolling
            ? abs(collectionView.contentOffset.y - targetOffset.y)
            : abs(collectionView.contentOffset.x - targetOffset.x)
        guard distance > 0.5 else {
            currentPage = pages[index]
            updateSessionState(isLoadingNextPage: nextPageTask != nil)
            finishPageTurn()
            return
        }

        collectionView.setContentOffset(targetOffset, animated: animated)
        currentPage = pages[index]
        updateSessionState(isLoadingNextPage: nextPageTask != nil)
        if !animated {
            finishPageTurn()
        }
    }

    private func finishPageTurn() {
        if usesVerticalScrolling {
            updateCurrentPageFromVisiblePage()
        } else {
            snapToNearestPageIfNeeded()
        }
        loadPreviousPageIfNeeded()
        loadNextPageIfNeeded()
        scheduleBackgroundWorkResume(after: 1.5)
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

        if indexPath.item <= 1 {
            loadPreviousPageIfNeeded()
        }
        if indexPath.item >= pages.count - 2 {
            loadNextPageIfNeeded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishPageTurn()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        finishPageTurn()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else {
            return
        }

        finishPageTurn()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        shouldScrollToPreviousPageAfterLoad = false
        shouldScrollToNextPageAfterLoad = false
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

extension ReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
            return true
        }
        return activeSettings.allowsSwipeBack
            && (navigationController?.viewControllers.count ?? 0) > 1
    }
}

private struct ReaderViewportMetrics: Equatable {
    let width: Int
    let height: Int
    let topInset: Int
    let leftInset: Int
    let bottomInset: Int
    let rightInset: Int

    init(size: CGSize, safeAreaInsets: UIEdgeInsets, scale: CGFloat) {
        let safeScale = max(CGFloat(1), scale)
        width = Int((size.width * safeScale).rounded())
        height = Int((size.height * safeScale).rounded())
        topInset = Int((safeAreaInsets.top * safeScale).rounded())
        leftInset = Int((safeAreaInsets.left * safeScale).rounded())
        bottomInset = Int((safeAreaInsets.bottom * safeScale).rounded())
        rightInset = Int((safeAreaInsets.right * safeScale).rounded())
    }
}

private struct ChapterByteRange {
    let title: String?
    let startByteOffset: UInt64
    let endByteOffset: UInt64

    init(title: String?, startByteOffset: UInt64, endByteOffset: UInt64) {
        self.title = title
        self.startByteOffset = startByteOffset
        self.endByteOffset = max(startByteOffset + 1, endByteOffset)
    }

    func progress(for byteOffset: UInt64) -> Float {
        let clampedByteOffset = min(max(byteOffset, startByteOffset), endByteOffset)
        let completedByteCount = clampedByteOffset - startByteOffset
        let totalByteCount = max(UInt64(1), endByteOffset - startByteOffset)
        return Float(Double(completedByteCount) / Double(totalByteCount))
    }

    func byteOffset(for progress: Double) -> UInt64 {
        let clampedProgress = min(1, max(0, progress))
        let totalByteCount = max(UInt64(1), endByteOffset - startByteOffset)
        let offset = startByteOffset + UInt64(clampedProgress * Double(totalByteCount))
        return min(endByteOffset - 1, offset)
    }
}
