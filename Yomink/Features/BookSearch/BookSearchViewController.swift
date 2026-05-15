import UIKit

final class BookSearchViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Item: Hashable {
        case message(String)
        case result(BookSearchResult)
    }

    var onResultSelected: ((BookSearchResult) -> Void)?

    private let book: BookRecord
    private let searchIndexService: SearchIndexService
    private let searchController = UISearchController(searchResultsController: nil)
    private var searchTask: Task<Void, Never>?
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

    init(book: BookRecord, searchIndexService: SearchIndexService) {
        self.book = book
        self.searchIndexService = searchIndexService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{4E66}\u{5185}\u{641C}\u{7D22}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureCollectionView()
        configureDataSource()
        applyItems([.message("\u{8F93}\u{5165}\u{5173}\u{952E}\u{8BCD}\u{641C}\u{7D22}")], animatingDifferences: false)
        searchIndexService.scheduleIndexing(bookID: book.id)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }

    deinit {
        searchTask?.cancel()
    }

    private func configureNavigation() {
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "\u{641C}\u{7D22}\u{672C}\u{4E66}\u{5185}\u{5BB9}"
        searchController.searchResultsUpdater = self
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
            case .message(let message):
                content.text = message
                content.secondaryText = nil
            case .result(let result):
                content.text = result.title
                content.secondaryText = result.snippet
                cell.accessories = [.disclosureIndicator()]
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

    private func performSearch(query: String) {
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            applyItems([.message("\u{8F93}\u{5165}\u{5173}\u{952E}\u{8BCD}\u{641C}\u{7D22}")], animatingDifferences: false)
            return
        }

        applyItems([.message("\u{641C}\u{7D22}\u{4E2D}")], animatingDifferences: false)
        searchIndexService.scheduleIndexing(bookID: book.id)
        searchTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let results = try await searchIndexService.search(bookID: book.id, query: trimmedQuery)
                guard !Task.isCancelled else {
                    return
                }
                let items = results.isEmpty
                    ? [Item.message("\u{6682}\u{65E0}\u{5339}\u{914D}\u{7ED3}\u{679C}")]
                    : results.map(Item.result)
                applyItems(items, animatingDifferences: true)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                applyItems([.message("\u{641C}\u{7D22}\u{5931}\u{8D25}")], animatingDifferences: true)
            }
        }
    }

    private func applyItems(_ items: [Item], animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension BookSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        performSearch(query: searchController.searchBar.text ?? "")
    }
}

extension BookSearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        if case .result(let result) = item {
            dismiss(animated: true) { [onResultSelected] in
                onResultSelected?(result)
            }
        }
    }
}
