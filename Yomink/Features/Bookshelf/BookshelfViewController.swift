import Combine
import UIKit

final class BookshelfViewController: UIViewController {
    private enum Section {
        case main
    }

    var onImportRequested: (() -> Void)?
    var onBookSelected: ((BookRecord) -> Void)?
    var onAppSettingsRequested: (() -> Void)?

    private let viewModel: BookshelfViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var dataSource: UICollectionViewDiffableDataSource<Section, BookshelfViewModel.Item>?
    private var groupList = BookGroupList(totalBookCount: 0, ungroupedBookCount: 0, groups: [])
    private var selectedBookIDs: Set<UUID> = []
    private var isSelectingBooks = false
    private var displayMode: BookshelfDisplayMode
    private let selectionMenuContainer = UIView()
    private let selectionMenuStack = UIStackView()
    private let deleteSelectionButton = UIButton(type: .system)
    private let moveSelectionButton = UIButton(type: .system)
    private let invertSelectionButton = UIButton(type: .system)
    private let finishSelectionButton = UIButton(type: .system)

    private lazy var collectionView: UICollectionView = {
        let backgroundColor = YominkTheme.background
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeCollectionLayout(displayMode: displayMode)
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = backgroundColor
        return collectionView
    }()

    init(viewModel: BookshelfViewModel) {
        self.viewModel = viewModel
        self.displayMode = viewModel.currentDisplayMode
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
        configureSelectionMenu()
        bindViewModel()
        viewModel.refresh()
    }

    func refreshBooks() {
        applyDisplayModeIfNeeded(animated: false)
        viewModel.refresh()
    }

    private func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.text"),
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
            )
        ]
    }

    private static func makeCollectionLayout(displayMode: BookshelfDisplayMode) -> UICollectionViewLayout {
        switch displayMode {
        case .list:
            return UICollectionViewCompositionalLayout { _, layoutEnvironment in
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.backgroundColor = YominkTheme.background
                configuration.showsSeparators = false
                return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            }
        case .grid:
            return UICollectionViewCompositionalLayout { _, layoutEnvironment in
                let availableWidth = layoutEnvironment.container.effectiveContentSize.width
                let columnCount = min(3, max(1, Int(availableWidth / 118)))
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalHeight(1)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(150)
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: groupSize,
                    subitem: item,
                    count: columnCount
                )

                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                return section
            }
        }
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

        let listRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, BookshelfViewModel.Item> {
            [weak self] cell, _, item in
            guard let self else {
                return
            }
            var content = makeCellContent(for: item, isGrid: false)
            configureSelectableImageIfNeeded(for: item, content: &content)

            cell.accessories = []
            switch item {
            case .book:
                if !isSelectingBooks {
                    cell.accessories = [.disclosureIndicator()]
                }
            case .emptyState:
                break
            }

            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }

        let gridRegistration = UICollectionView.CellRegistration<UICollectionViewCell, BookshelfViewModel.Item> {
            [weak self] cell, _, item in
            guard let self else {
                return
            }

            var content = makeCellContent(for: item, isGrid: true)
            configureSelectableImageIfNeeded(for: item, content: &content)
            cell.contentConfiguration = content

            var backgroundConfiguration = UIBackgroundConfiguration.clear()
            if case .book = item {
                backgroundConfiguration.backgroundColor = .secondarySystemBackground
                backgroundConfiguration.cornerRadius = 8
            }
            cell.backgroundConfiguration = backgroundConfiguration
        }

        dataSource = UICollectionViewDiffableDataSource<Section, BookshelfViewModel.Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else {
                return UICollectionViewCell()
            }

            switch displayMode {
            case .list:
                return collectionView.dequeueConfiguredReusableCell(
                    using: listRegistration,
                    for: indexPath,
                    item: item
                )
            case .grid:
                return collectionView.dequeueConfiguredReusableCell(
                    using: gridRegistration,
                    for: indexPath,
                    item: item
                )
            }
        }

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        collectionView.addGestureRecognizer(longPressGesture)
    }

    private func makeCellContent(
        for item: BookshelfViewModel.Item,
        isGrid: Bool
    ) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.color = YominkTheme.primaryText
        content.secondaryTextProperties.color = YominkTheme.secondaryText
        content.textProperties.numberOfLines = isGrid ? 2 : 1
        content.secondaryTextProperties.numberOfLines = isGrid ? 2 : 1

        if isGrid {
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
            content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        }

        switch item {
        case .book(let bookItem):
            content.text = bookItem.book.title
            content.secondaryText = Self.subtitle(for: bookItem)
            content.image = UIImage(systemName: "book.closed")
        case .emptyState:
            content.text = "\u{5C1A}\u{672A}\u{5BFC}\u{5165}\u{4E66}\u{7C4D}"
            content.secondaryText = "\u{4ECE}\u{53F3}\u{4E0A}\u{89D2}\u{6DFB}\u{52A0} TXT \u{6587}\u{4EF6}\u{5F00}\u{59CB}\u{9605}\u{8BFB}"
            content.image = UIImage(systemName: "tray")
        }

        return content
    }

    private func configureSelectableImageIfNeeded(
        for item: BookshelfViewModel.Item,
        content: inout UIListContentConfiguration
    ) {
        guard isSelectingBooks,
              case .book(let bookItem) = item else {
            return
        }

        let isSelected = selectedBookIDs.contains(bookItem.book.id)
        content.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        content.imageProperties.tintColor = isSelected ? view.tintColor : YominkTheme.secondaryText
    }

    private func configureSelectionMenu() {
        selectionMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        selectionMenuContainer.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        selectionMenuContainer.layer.cornerRadius = 8
        selectionMenuContainer.layer.shadowColor = UIColor.black.cgColor
        selectionMenuContainer.layer.shadowOpacity = 0.18
        selectionMenuContainer.layer.shadowRadius = 12
        selectionMenuContainer.layer.shadowOffset = CGSize(width: 0, height: 5)
        selectionMenuContainer.alpha = 0
        selectionMenuContainer.isHidden = true
        selectionMenuContainer.transform = CGAffineTransform(translationX: 0, y: 12)
        view.addSubview(selectionMenuContainer)

        selectionMenuStack.translatesAutoresizingMaskIntoConstraints = false
        selectionMenuStack.axis = .horizontal
        selectionMenuStack.alignment = .center
        selectionMenuStack.distribution = .fillEqually
        selectionMenuStack.spacing = 4
        selectionMenuContainer.addSubview(selectionMenuStack)

        configureSelectionMenuButton(
            deleteSelectionButton,
            title: "\u{5220}\u{9664}",
            systemName: "trash",
            action: #selector(deleteSelectedBooks)
        )
        configureSelectionMenuButton(
            moveSelectionButton,
            title: "\u{79FB}\u{52A8}",
            systemName: "folder",
            action: #selector(moveSelectedBooks)
        )
        configureSelectionMenuButton(
            invertSelectionButton,
            title: "\u{53CD}\u{9009}",
            systemName: "arrow.triangle.2.circlepath",
            action: #selector(invertSelection)
        )
        configureSelectionMenuButton(
            finishSelectionButton,
            title: "\u{5B8C}\u{6210}",
            systemName: "checkmark",
            action: #selector(cancelSelection)
        )

        deleteSelectionButton.configuration?.baseForegroundColor = .systemRed
        [
            deleteSelectionButton,
            moveSelectionButton,
            invertSelectionButton,
            finishSelectionButton
        ].forEach { button in
            selectionMenuStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            selectionMenuContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            selectionMenuContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            selectionMenuContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            selectionMenuContainer.heightAnchor.constraint(equalToConstant: 62),

            selectionMenuStack.topAnchor.constraint(equalTo: selectionMenuContainer.topAnchor, constant: 5),
            selectionMenuStack.leadingAnchor.constraint(equalTo: selectionMenuContainer.leadingAnchor, constant: 8),
            selectionMenuStack.trailingAnchor.constraint(equalTo: selectionMenuContainer.trailingAnchor, constant: -8),
            selectionMenuStack.bottomAnchor.constraint(equalTo: selectionMenuContainer.bottomAnchor, constant: -5)
        ])
        updateSelectionMenuState()
    }

    private func configureSelectionMenuButton(_ button: UIButton, title: String, systemName: String, action: Selector) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: systemName)
        configuration.imagePlacement = .top
        configuration.imagePadding = 3
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func bindViewModel() {
        viewModel.items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.handleItemsChanged(items)
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

    private func handleItemsChanged(_ items: [BookshelfViewModel.Item]) {
        applyDisplayModeIfNeeded(animated: false)
        if isSelectingBooks {
            selectedBookIDs.formIntersection(Set(bookIDs(in: items)))
        }
        applySnapshot(items: items)
        updateSelectionMenuState()
    }

    private func applyDisplayModeIfNeeded(animated: Bool) {
        let updatedDisplayMode = viewModel.currentDisplayMode
        guard displayMode != updatedDisplayMode else {
            return
        }

        displayMode = updatedDisplayMode
        collectionView.setCollectionViewLayout(
            Self.makeCollectionLayout(displayMode: updatedDisplayMode),
            animated: animated
        )
        reloadSnapshotForDisplayModeChange()
    }

    private func reloadSnapshotForDisplayModeChange() {
        guard var snapshot = dataSource?.snapshot(),
              !snapshot.itemIdentifiers.isEmpty else {
            return
        }

        snapshot.reloadItems(snapshot.itemIdentifiers)
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
        drawer.onAppSettings = { [weak self] in
            self?.onAppSettingsRequested?()
        }

        let navigationController = DrawerNavigationController(rootViewController: drawer, edge: .left)
        navigationController.modalPresentationStyle = .custom
        navigationController.transitioningDelegate = self
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

        let navigationController = DrawerNavigationController(rootViewController: menu, edge: .right)
        navigationController.modalPresentationStyle = .custom
        navigationController.transitioningDelegate = self
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

    @objc private func invertSelection() {
        guard isSelectingBooks else {
            return
        }

        let allBookIDs = Set(bookIDs(in: viewModel.items.value))
        selectedBookIDs = allBookIDs.subtracting(selectedBookIDs)
        refreshVisibleSnapshot()
        updateSelectionMenuState()
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
        setSelectionMenuVisible(true, animated: true)
        updateSelectionMenuState()
        refreshVisibleSnapshot()
    }

    private func endSelectionMode() {
        guard isSelectingBooks else {
            return
        }

        isSelectingBooks = false
        selectedBookIDs.removeAll()
        configureNavigationItems()
        setSelectionMenuVisible(false, animated: true)
        updateSelectionMenuState()
        refreshVisibleSnapshot()
    }

    private func toggleSelection(for bookID: UUID) {
        if selectedBookIDs.contains(bookID) {
            selectedBookIDs.remove(bookID)
        } else {
            selectedBookIDs.insert(bookID)
        }

        refreshVisibleSnapshot()
        updateSelectionMenuState()
    }

    private func performDeleteSelectedBooks() {
        let bookIDs = Array(selectedBookIDs)
        Task { @MainActor [weak self] in
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
        guard var snapshot = dataSource?.snapshot() else {
            applySnapshot(items: viewModel.items.value)
            return
        }

        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func setSelectionMenuVisible(_ isVisible: Bool, animated: Bool) {
        let bottomInset: CGFloat = isVisible ? 88 : 0
        collectionView.contentInset.bottom = bottomInset
        collectionView.verticalScrollIndicatorInsets.bottom = bottomInset

        let updates = {
            self.selectionMenuContainer.alpha = isVisible ? 1 : 0
            self.selectionMenuContainer.transform = isVisible ? .identity : CGAffineTransform(translationX: 0, y: 12)
        }

        selectionMenuContainer.isHidden = false
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                updates()
            } completion: { _ in
                self.selectionMenuContainer.isHidden = !isVisible
            }
        } else {
            updates()
            selectionMenuContainer.isHidden = !isVisible
        }
    }

    private func updateSelectionMenuState() {
        let hasSelection = !selectedBookIDs.isEmpty
        deleteSelectionButton.isEnabled = hasSelection
        moveSelectionButton.isEnabled = hasSelection
        invertSelectionButton.isEnabled = isSelectingBooks && !bookIDs(in: viewModel.items.value).isEmpty
        finishSelectionButton.isEnabled = isSelectingBooks
    }

    private func bookIDs(in items: [BookshelfViewModel.Item]) -> [UUID] {
        items.compactMap { item in
            guard case .book(let bookItem) = item else {
                return nil
            }
            return bookItem.book.id
        }
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
        guard !isSelectingBooks else {
            return nil
        }

        guard let item = dataSource?.itemIdentifier(for: indexPath),
              case .book(let bookItem) = item else {
            return nil
        }

        let deleteAction = UIContextualAction(
            style: .destructive,
            title: "\u{5220}\u{9664}"
        ) { [weak self] _, _, completion in
            self?.beginSelectionMode(selecting: bookItem.book.id)
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
        return nil
    }
}

extension BookshelfViewController: UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        let edge = (presented as? DrawerNavigationController)?.edge ?? .left
        return DrawerPresentationController(
            presentedViewController: presented,
            presenting: presenting,
            edge: edge
        )
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        let edge = (presented as? DrawerNavigationController)?.edge ?? .left
        return DrawerTransitionAnimator(edge: edge, isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let edge = (dismissed as? DrawerNavigationController)?.edge ?? .left
        return DrawerTransitionAnimator(edge: edge, isPresenting: false)
    }
}

private enum DrawerEdge {
    case left
    case right
}

private final class DrawerNavigationController: UINavigationController {
    let edge: DrawerEdge

    init(rootViewController: UIViewController, edge: DrawerEdge) {
        self.edge = edge
        super.init(rootViewController: rootViewController)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        nil
    }
}

private final class DrawerPresentationController: UIPresentationController {
    private let dimmingView = UIView()
    private let edge: DrawerEdge

    init(
        presentedViewController: UIViewController,
        presenting presentingViewController: UIViewController?,
        edge: DrawerEdge
    ) {
        self.edge = edge
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        dimmingView.alpha = 0
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissPresented)))
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else {
            return .zero
        }
        let width = min(containerView.bounds.width * 0.82, 340)
        let x = edge == .left ? CGFloat(0) : containerView.bounds.width - width
        return CGRect(x: x, y: 0, width: width, height: containerView.bounds.height)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else {
            return
        }
        dimmingView.frame = containerView.bounds
        containerView.insertSubview(dimmingView, at: 0)
        presentedViewController.transitionCoordinator?.animate { [dimmingView] _ in
            dimmingView.alpha = 1
        }
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate { [dimmingView] _ in
            dimmingView.alpha = 0
        }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        dimmingView.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    @objc private func dismissPresented() {
        presentedViewController.dismiss(animated: true)
    }
}

private final class DrawerTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let edge: DrawerEdge
    private let isPresenting: Bool

    init(edge: DrawerEdge, isPresenting: Bool) {
        self.edge = edge
        self.isPresenting = isPresenting
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.22
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if isPresenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }

    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        guard let view = transitionContext.view(forKey: .to),
              let viewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: viewController)
        view.frame = offscreenFrame(from: finalFrame, in: containerView)
        containerView.addSubview(view)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            view.frame = finalFrame
        } completion: { _ in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }

    private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        guard let view = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        let finalFrame = offscreenFrame(from: view.frame, in: containerView)
        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            view.frame = finalFrame
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if completed {
                view.removeFromSuperview()
            }
            transitionContext.completeTransition(completed)
        }
    }

    private func offscreenFrame(from frame: CGRect, in containerView: UIView) -> CGRect {
        var offscreenFrame = frame
        switch edge {
        case .left:
            offscreenFrame.origin.x = -frame.width
        case .right:
            offscreenFrame.origin.x = containerView.bounds.width
        }
        return offscreenFrame
    }
}
