import Combine
import UIKit

final class BookshelfViewController: UIViewController {
    private enum Section {
        case main
    }

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
            case .emptyState:
                content.text = "尚未导入书籍"
                content.secondaryText = "从右上角添加 TXT 文件开始阅读"
                content.image = UIImage(systemName: "book.closed")
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
        presentPlaceholder(title: "分组", message: "书架分组将在后续阶段接入。")
    }

    @objc private func showImportOptions() {
        presentPlaceholder(title: "导入", message: "文件导入将在阅读引擎 MVP 后接入。")
    }

    @objc private func showSearch() {
        presentPlaceholder(title: "搜索", message: "书名搜索和历史记录将在书架阶段接入。")
    }

    private func presentPlaceholder(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
