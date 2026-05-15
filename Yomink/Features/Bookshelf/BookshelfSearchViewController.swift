import UIKit

final class BookshelfSearchViewController: UIViewController {
    private enum Section {
        case history
        case results
    }

    private enum Item: Hashable {
        case history(String)
        case clearHistory
        case message(String)
        case result(BookshelfBookItem)
    }

    var onQueryChanged: ((String) -> [BookshelfBookItem])?
    var onQueryCommitted: ((String) -> Void)?
    var onClearHistory: (() -> Void)?
    var onBookSelected: ((BookRecord) -> Void)?

    private let searchController = UISearchController(searchResultsController: nil)
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private var history: [String]
    private var results: [BookshelfBookItem] = []
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            guard let section = self?.dataSource?.snapshot().sectionIdentifiers[safe: sectionIndex] else {
                return Self.makeListSection(layoutEnvironment: layoutEnvironment)
            }

            switch section {
            case .history:
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .estimated(90),
                    heightDimension: .absolute(34)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .estimated(90),
                    heightDimension: .absolute(34)
                )
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = 8
                section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                return section
            case .results:
                return Self.makeListSection(layoutEnvironment: layoutEnvironment)
            }
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        return collectionView
    }()

    init(history: [String]) {
        self.history = history
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureNavigation()
        configureBlur()
        configureCollectionView()
        configureDataSource()
        applySnapshot(message: "\u{8F93}\u{5165}\u{4E66}\u{540D}\u{641C}\u{7D22}")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.searchBar.becomeFirstResponder()
    }

    func updateHistory(_ history: [String]) {
        self.history = history
        applySnapshot(message: nil)
    }

    private func configureNavigation() {
        title = "\u{641C}\u{7D22}"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "\u{641C}\u{7D22}\u{4E66}\u{540D}"
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
    }

    private func configureBlur() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        let chipRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { cell, _, item in
            var configuration = UIListContentConfiguration.cell()
            configuration.textProperties.color = YominkTheme.primaryText
            configuration.textProperties.alignment = .center

            switch item {
            case .history(let query):
                configuration.text = query
            case .clearHistory:
                configuration.text = "\u{6E05}\u{7A7A}"
            default:
                configuration.text = nil
            }

            var background = UIBackgroundConfiguration.listPlainCell()
            background.backgroundColor = UIColor.white.withAlphaComponent(0.5)
            background.cornerRadius = 16
            cell.backgroundConfiguration = background
            cell.contentConfiguration = configuration
        }

        let listRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = UIListContentConfiguration.subtitleCell()
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText

            switch item {
            case .message(let message):
                content.text = message
                content.secondaryText = nil
                content.image = UIImage(systemName: "magnifyingglass")
                cell.accessories = []
            case .result(let item):
                content.text = item.book.title
                content.secondaryText = Self.subtitle(for: item)
                content.image = UIImage(systemName: "book.closed")
                cell.accessories = [.disclosureIndicator()]
            default:
                content.text = nil
            }

            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .history, .clearHistory:
                return collectionView.dequeueConfiguredReusableCell(using: chipRegistration, for: indexPath, item: item)
            case .message, .result:
                return collectionView.dequeueConfiguredReusableCell(using: listRegistration, for: indexPath, item: item)
            }
        }
    }

    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            applySnapshot(message: "\u{8F93}\u{5165}\u{4E66}\u{540D}\u{641C}\u{7D22}")
            return
        }

        results = onQueryChanged?(trimmedQuery) ?? []
        applySnapshot(message: results.isEmpty ? "\u{6682}\u{65E0}\u{5339}\u{914D}\u{4E66}\u{7C4D}" : nil)
    }

    private func applySnapshot(message: String?) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.history, .results])

        var historyItems = history.map(Item.history)
        if !historyItems.isEmpty {
            historyItems.append(.clearHistory)
        }
        snapshot.appendItems(historyItems, toSection: .history)

        let resultItems: [Item]
        if let message {
            resultItems = [.message(message)]
        } else {
            resultItems = results.map(Item.result)
        }
        snapshot.appendItems(resultItems, toSection: .results)
        dataSource?.apply(snapshot, animatingDifferences: true)
    }

    private static func makeListSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = true
        return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
    }

    private static func subtitle(for item: BookshelfBookItem) -> String {
        "\(Int((item.readingProgress * 100).rounded()))%"
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension BookshelfSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        performSearch(query: searchController.searchBar.text ?? "")
    }
}

extension BookshelfSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let query = searchBar.text ?? ""
        onQueryCommitted?(query)
        updateHistory(history)
    }
}

extension BookshelfSearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .history(let query):
            searchController.searchBar.text = query
            performSearch(query: query)
            onQueryCommitted?(query)
        case .clearHistory:
            onClearHistory?()
            history = []
            applySnapshot(message: results.isEmpty ? "\u{8F93}\u{5165}\u{4E66}\u{540D}\u{641C}\u{7D22}" : nil)
        case .result(let item):
            dismiss(animated: true) { [onBookSelected] in
                onBookSelected?(item.book)
            }
        case .message:
            break
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
