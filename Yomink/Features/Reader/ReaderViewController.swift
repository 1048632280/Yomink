import UIKit

final class ReaderViewController: UIViewController {
    private enum Section {
        case main
    }

    private let book: BookRecord
    private let openingService: ReaderOpeningService
    private let pagingService: ReaderPagingService
    private let readingSettingsStore: ReadingSettingsStore
    private let progressStore: ReadingProgressStore
    private let collectionView: UICollectionView

    private var dataSource: UICollectionViewDiffableDataSource<Section, ReaderPage>?
    private var pages: [ReaderPage] = []
    private var currentPage: ReaderPage?
    private var openingTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var didStartOpening = false
    private var didReachEndOfBook = false
    private var activeLayout = ReadingSettings.standard.layout

    init(
        book: BookRecord,
        openingService: ReaderOpeningService,
        pagingService: ReaderPagingService,
        readingSettingsStore: ReadingSettingsStore,
        progressStore: ReadingProgressStore
    ) {
        self.book = book
        self.openingService = openingService
        self.pagingService = pagingService
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
        view.backgroundColor = YominkTheme.background
        configureCollectionView()
        configureDataSource()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveCurrentProgressForBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
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
        NotificationCenter.default.removeObserver(self)
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = YominkTheme.background
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
            cell.configure(page: page, layout: activeLayout)
            return cell
        }
    }

    private func openFirstPageIfNeeded() {
        guard !didStartOpening,
              collectionView.bounds.width > 1,
              collectionView.bounds.height > 1 else {
            return
        }

        didStartOpening = true
        var settings = readingSettingsStore.load()
        settings.layout.viewportSize = collectionView.bounds.size
        activeLayout = settings.layout

        let request = ReaderOpeningRequest(
            bookID: book.id,
            viewportSize: collectionView.bounds.size,
            layout: settings.layout,
            preferredByteOffset: nil
        )

        openingTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await openingService.openFirstPage(request)
                applyInitialPage(result.page)
                loadNextPageIfNeeded()
            } catch {
                showOpeningError()
            }
        }
    }

    private func applyInitialPage(_ page: ReaderPage) {
        pages = [page]
        currentPage = page
        applyPagesSnapshot()
    }

    private func appendPage(_ page: ReaderPage) {
        guard !pages.contains(where: { $0.startByteOffset == page.startByteOffset }) else {
            return
        }
        pages.append(page)
        applyPagesSnapshot()
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
            layout: activeLayout
        )

        nextPageTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let nextPage = try await pagingService.page(request)
                nextPageTask = nil
                guard let nextPage else {
                    didReachEndOfBook = true
                    return
                }
                appendPage(nextPage)
            } catch {
                nextPageTask = nil
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
    }

    private func showOpeningError() {
        let alert = UIAlertController(title: "打开失败", message: "无法打开这本 TXT。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension ReaderViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard pages.indices.contains(indexPath.item) else {
            return
        }

        currentPage = pages[indexPath.item]
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
