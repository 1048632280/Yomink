import UIKit

final class BookshelfAddMenuViewController: UIViewController {
    private enum Section {
        case main
    }

    private enum Item: Hashable {
        case importFile
        case recent
    }

    var onImportRequested: (() -> Void)?
    var onRecentRequested: (() -> Void)?

    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.backgroundColor = YominkTheme.background
            configuration.showsSeparators = true
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = YominkTheme.background
        return collectionView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{6DFB}\u{52A0}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
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
            var content = UIListContentConfiguration.cell()
            content.textProperties.color = YominkTheme.primaryText
            cell.accessories = [.disclosureIndicator()]

            switch item {
            case .importFile:
                content.text = "\u{4ECE}\u{6587}\u{4EF6}\u{5BFC}\u{5165}"
                content.image = UIImage(systemName: "doc.badge.plus")
            case .recent:
                content.text = "\u{8DB3}\u{8FF9}"
                content.image = UIImage(systemName: "clock")
            }

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
        snapshot.appendItems([.importFile, .recent], toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension BookshelfAddMenuViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath) else {
            return
        }

        dismiss(animated: true) { [onImportRequested, onRecentRequested] in
            switch item {
            case .importFile:
                onImportRequested?()
            case .recent:
                onRecentRequested?()
            }
        }
    }
}
