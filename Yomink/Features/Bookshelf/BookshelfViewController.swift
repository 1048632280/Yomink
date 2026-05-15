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
    private var groupList = BookGroupList(totalBookCount: 0, ungroupedBookCount: 0, groups: [])
    private var selectedBookIDs: Set<UUID> = []
    private var isSelectingBooks = false

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
        configureToolbar()
        bindViewModel()
        viewModel.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
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
                action: #selector(showAddMenu)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "magnifyingglass"),
                style: .plain,
                target: self,
                action: #selector(showSearch)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "arrow.up.arrow.down"),
                style: .plain,
                target: self,
                action: #selector(showSortOptions)
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

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, BookshelfViewModel.Item> {
            [weak self] cell, _, item in
            guard let self else {
                return
            }

            var content = UIListContentConfiguration.subtitleCell()
            content.textProperties.color = YominkTheme.primaryText
            content.secondaryTextProperties.color = YominkTheme.secondaryText

            switch item {
            case .book(let bookItem):
                content.text = bookItem.book.title
                content.secondaryText = Self.subtitle(for: bookItem)
                content.image = UIImage(systemName: "book.closed")
                if isSelectingBooks {
                    cell.accessories = selectedBookIDs.contains(bookItem.book.id)
                        ? [.checkmark()]
                        : []
                } else {
                    cell.accessories = [.disclosureIndicator()]
                }
            case .emptyState:
                content.text = "\u{5C1A}\u{672A}\u{5BFC}\u{5165}\u{4E66}\u{7C4D}"
                content.secondaryText = "\u{4ECE}\u{53F3}\u{4E0A}\u{89D2}\u{6DFB}\u{52A0} TXT \u{6587}\u{4EF6}\u{5F00}\u{59CB}\u{9605}\u{8BFB}"
                content.image = UIImage(systemName: "tray")
                cell.accessories = []
            }

            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, BookshelfViewModel.Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        collectionView.addGestureRecognizer(longPressGesture)
    }

    private func configureToolbar() {
        toolbarItems = [
            UIBarButtonItem(
                title: "\u{79FB}\u{52A8}",
                style: .plain,
                target: self,
                action: #selector(moveSelectedBooks)
            ),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                title: "\u{5220}\u{9664}",
                style: .plain,
                target: self,
                action: #selector(deleteSelectedBooks)
            )
        ]
        navigationController?.setToolbarHidden(true, animated: false)
    }

    private func bindViewModel() {
        viewModel.items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.applySnapshot(items: items)
            }
            .store(in: &cancellables)

        viewModel.groupList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] groupList in
                self?.groupList = groupList
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
        endSelectionMode()
        let drawer = BookshelfGroupDrawerViewController(
            groupList: groupList,
            selectedFilter: viewModel.currentGroupFilter
        )
        drawer.onFilterSelected = { [weak self] filter in
            self?.viewModel.selectGroupFilter(filter)
        }
        drawer.onManageGroups = { [weak self] in
            self?.showGroupManagement()
        }

        let navigationController = UINavigationController(rootViewController: drawer)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    @objc private func showAddMenu() {
        endSelectionMode()
        let menu = BookshelfAddMenuViewController()
        menu.onImportRequested = { [weak self] in
            self?.onImportRequested?()
        }
        menu.onRecentRequested = { [weak self] in
            self?.showRecentBooks()
        }

        let navigationController = UINavigationController(rootViewController: menu)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    @objc private func showSearch() {
        endSelectionMode()
        let searchViewController = BookshelfSearchViewController(history: viewModel.searchHistory)
        searchViewController.onQueryChanged = { [weak self] query in
            self?.searchBooks(query: query) ?? []
        }
        searchViewController.onQueryCommitted = { [weak self, weak searchViewController] query in
            guard let self else {
                return
            }
            viewModel.rememberSearch(query)
            searchViewController?.updateHistory(viewModel.searchHistory)
        }
        searchViewController.onClearHistory = { [weak self] in
            self?.viewModel.clearSearchHistory()
        }
        searchViewController.onBookSelected = { [weak self] book in
            self?.onBookSelected?(book)
        }

        let navigationController = UINavigationController(rootViewController: searchViewController)
        navigationController.modalPresentationStyle = .overFullScreen
        navigationController.modalTransitionStyle = .crossDissolve
        navigationController.view.backgroundColor = .clear
        present(navigationController, animated: true)
    }

    @objc private func showSortOptions() {
        endSelectionMode()
        let alert = UIAlertController(title: "\u{6392}\u{5E8F}", message: nil, preferredStyle: .actionSheet)
        for sortMode in BookshelfSortMode.allCases {
            alert.addAction(
                UIAlertAction(title: sortMode.title, style: .default) { [weak self] _ in
                    self?.viewModel.setSortMode(sortMode)
                }
            )
        }
        alert.addAction(UIAlertAction(title: "\u{53D6}\u{6D88}", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(alert, animated: true)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else {
            return
        }

        let location = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location),
              let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let bookItem) = item else {
            return
        }

        beginSelectionMode(selecting: bookItem.book.id)
    }

    @objc private func cancelSelection() {
        endSelectionMode()
    }

    @objc private func moveSelectedBooks() {
        guard !selectedBookIDs.isEmpty else {
            return
        }

        let moveViewController = BookMoveGroupViewController(groups: groupList.groups)
        moveViewController.onGroupSelected = { [weak self] groupID in
            guard let self else {
                return
            }

            do {
                try viewModel.moveBooks(Array(selectedBookIDs), toGroupID: groupID)
                endSelectionMode()
            } catch {
                presentError(title: "\u{79FB}\u{52A8}\u{5931}\u{8D25}")
            }
        }

        let navigationController = UINavigationController(rootViewController: moveViewController)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }

    @objc private func deleteSelectedBooks() {
        guard !selectedBookIDs.isEmpty else {
            return
        }

        let count = selectedBookIDs.count
        let alert = UIAlertController(
            title: "\u{5220}\u{9664}\u{4E66}\u{7C4D}",
            message: "\u{5C06}\u{540C}\u{65F6}\u{6E05}\u{7406}\u{7F13}\u{5B58}\u{3001}\u{8FDB}\u{5EA6}\u{3001}\u{4E66}\u{7B7E}\u{3001}\u{76EE}\u{5F55}\u{548C}\u{641C}\u{7D22}\u{7D22}\u{5F15}\u{3002}",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "\u{53D6}\u{6D88}", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "\u{5220}\u{9664} \(count)", style: .destructive) { [weak self] _ in
                self?.performDeleteSelectedBooks()
            }
        )
        present(alert, animated: true)
    }

    private func showGroupManagement() {
        let viewController = GroupManagementViewController(groups: groupList.groups)
        viewController.onCreateGroup = { [weak self, weak viewController] name in
            guard let self else {
                return
            }
            performGroupMutation {
                try viewModel.createGroup(name: name)
            }
            viewController?.update(groups: viewModel.groupList.value.groups)
        }
        viewController.onRenameGroup = { [weak self, weak viewController] id, name in
            guard let self else {
                return
            }
            performGroupMutation {
                try viewModel.renameGroup(id: id, name: name)
            }
            viewController?.update(groups: viewModel.groupList.value.groups)
        }
        viewController.onDeleteGroup = { [weak self, weak viewController] id in
            guard let self else {
                return
            }
            performGroupMutation {
                try viewModel.deleteGroup(id: id)
            }
            viewController?.update(groups: viewModel.groupList.value.groups)
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func showRecentBooks() {
        do {
            let viewController = BookshelfRecentViewController(items: try viewModel.recentBooks())
            viewController.onBookSelected = { [weak self] book in
                self?.onBookSelected?(book)
            }
            navigationController?.pushViewController(viewController, animated: true)
        } catch {
            presentError(title: "\u{8DB3}\u{8FF9}\u{52A0}\u{8F7D}\u{5931}\u{8D25}")
        }
    }

    private func searchBooks(query: String) -> [BookshelfBookItem] {
        do {
            return try viewModel.searchBooks(query: query)
        } catch {
            return []
        }
    }

    private func beginSelectionMode(selecting bookID: UUID) {
        isSelectingBooks = true
        selectedBookIDs = [bookID]
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelSelection)
            )
        ]
        navigationController?.setToolbarHidden(false, animated: true)
        refreshVisibleSnapshot()
    }

    private func endSelectionMode() {
        guard isSelectingBooks else {
            return
        }

        isSelectingBooks = false
        selectedBookIDs.removeAll()
        configureNavigationItems()
        navigationController?.setToolbarHidden(true, animated: true)
        refreshVisibleSnapshot()
    }

    private func toggleSelection(for bookID: UUID) {
        if selectedBookIDs.contains(bookID) {
            selectedBookIDs.remove(bookID)
        } else {
            selectedBookIDs.insert(bookID)
        }

        if selectedBookIDs.isEmpty {
            endSelectionMode()
        } else {
            refreshVisibleSnapshot()
        }
    }

    private func performDeleteSelectedBooks() {
        let bookIDs = Array(selectedBookIDs)
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await viewModel.deleteBooks(bookIDs)
                isSelectingBooks = true
                viewModel.refresh()
                endSelectionMode()
            } catch {
                presentError(title: "\u{5220}\u{9664}\u{5931}\u{8D25}")
            }
        }
    }

    private func performGroupMutation(_ mutation: () throws -> Void) {
        do {
            try mutation()
        } catch {
            presentError(title: "\u{5206}\u{7EC4}\u{64CD}\u{4F5C}\u{5931}\u{8D25}")
        }
    }

    private func refreshVisibleSnapshot() {
        applySnapshot(items: viewModel.items.value)
    }

    private func presentError(title: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        present(alert, animated: true)
    }

    private static func subtitle(for item: BookshelfBookItem) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.book.fileSize), countStyle: .file)
        let percent = Int((item.readingProgress * 100).rounded())
        return "\(percent)% \u{00B7} \(size) \u{00B7} \(item.book.encoding.rawValue)"
    }
}

extension BookshelfViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let bookItem) = item else {
            return
        }

        if isSelectingBooks {
            toggleSelection(for: bookItem.book.id)
        } else {
            onBookSelected?(bookItem.book)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let bookItem) = item else {
            return nil
        }

        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "\u{5220}\u{9664}"
        ) { [weak self] _, _, completion in
            self?.selectedBookIDs = [bookItem.book.id]
            self?.isSelectingBooks = true
            self?.deleteSelectedBooks()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let bookItem) = item else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: "\u{79FB}\u{52A8}\u{5230}\u{5206}\u{7EC4}",
                    image: UIImage(systemName: "folder")
                ) { _ in
                    self?.selectedBookIDs = [bookItem.book.id]
                    self?.isSelectingBooks = true
                    self?.moveSelectedBooks()
                },
                UIAction(
                    title: "\u{5220}\u{9664}",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.selectedBookIDs = [bookItem.book.id]
                    self?.deleteSelectedBooks()
                }
            ])
        }
    }
}
