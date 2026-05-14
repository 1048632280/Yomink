import Combine
import UIKit

final class BookshelfViewController: UIViewController {
    private enum Section {
        case main
    }

    var onImportRequested: (() -> Void)?
    var onBookSelected: ((BookRecord) -> Void)?

    private let viewModel: BookshelfViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var dataSource: UICollectionViewDiffableDataSource<Section, BookshelfViewModel.Item>?

    private lazy var collectionView: UICollectionView = {
        let backgroundColor = YominkTheme.background
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.backgroundColor = backgroundColor
            configuration.showsSeparators = false
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = backgroundColor
        return collectionView
    }()

    init(viewModel: BookshelfViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = YominkTheme.background
        title = viewModel.title
        configureNavigationItems()
        configureCollectionView()
        bindViewModel()
        viewModel.refresh()
    }

    func refreshBooks() {
        viewModel.refresh()
    }

    private func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "folder"),
            style: .plain,
            target: self,
            action: #selector(showGroups)
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(showImportOptions)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "magnifyingglass"),
                style: .plain,
                target: self,
                action: #selector(showSearch)
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

        let primaryTextColor = YominkTheme.primaryText
        let secondaryTextColor = YominkTheme.secondaryText
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, BookshelfViewModel.Item> { cell, _, item in
            var content = UIListContentConfiguration.cell()
            switch item {
            case .book(let book):
                content.text = book.title
                content.secondaryText = Self.subtitle(for: book)
                content.image = UIImage(systemName: "book.closed")
                cell.accessories = [.disclosureIndicator()]
            case .emptyState:
                content.text = "\u{5C1A}\u{672A}\u{5BFC}\u{5165}\u{4E66}\u{7C4D}"
                content.secondaryText = "\u{4ECE}\u{53F3}\u{4E0A}\u{89D2}\u{6DFB}\u{52A0} TXT \u{6587}\u{4EF6}\u{5F00}\u{59CB}\u{9605}\u{8BFB}"
                content.image = UIImage(systemName: "tray")
                cell.accessories = []
            }
            content.textProperties.color = primaryTextColor
            content.secondaryTextProperties.color = secondaryTextColor
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, BookshelfViewModel.Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
    }

    private func bindViewModel() {
        viewModel.items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.applySnapshot(items: items)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(items: [BookshelfViewModel.Item]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, BookshelfViewModel.Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    @objc private func showGroups() {
        presentPlaceholder(
            title: "\u{5206}\u{7EC4}",
            message: "\u{4E66}\u{67B6}\u{5206}\u{7EC4}\u{5C06}\u{5728}\u{540E}\u{7EED}\u{9636}\u{6BB5}\u{63A5}\u{5165}\u{3002}"
        )
    }

    @objc private func showImportOptions() {
        onImportRequested?()
    }

    @objc private func showSearch() {
        presentPlaceholder(
            title: "\u{641C}\u{7D22}",
            message: "\u{4E66}\u{540D}\u{641C}\u{7D22}\u{548C}\u{5386}\u{53F2}\u{8BB0}\u{5F55}\u{5C06}\u{5728}\u{540E}\u{7EED}\u{9636}\u{6BB5}\u{63A5}\u{5165}\u{3002}"
        )
    }

    private func presentPlaceholder(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        present(alert, animated: true)
    }

    private static func subtitle(for book: BookRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(book.fileSize), countStyle: .file)
        return "\(size) \u{00B7} \(book.encoding.rawValue)"
    }
}

extension BookshelfViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let book) = item else {
            return
        }
        onBookSelected?(book)
    }
}
