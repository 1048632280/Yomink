import Combine
import Foundation

@MainActor
final class BookshelfViewModel {
    enum Item: Hashable {
        case book(BookshelfBookItem)
        case emptyState
    }

    let title = "Yomink"
    let items = CurrentValueSubject<[Item], Never>([.emptyState])
    let groupList = CurrentValueSubject<BookGroupList, Never>(
        BookGroupList(totalBookCount: 0, ungroupedBookCount: 0, groups: [])
    )

    private let bookRepository: BookRepository
    private let groupRepository: BookGroupRepository
    private let appSettingsStore: AppSettingsStore
    private let deletionService: BookDeletionService
    private var selectedGroupFilter: BookshelfGroupFilter = .all
    private var searchText = ""

    init(
        bookRepository: BookRepository,
        groupRepository: BookGroupRepository,
        appSettingsStore: AppSettingsStore,
        deletionService: BookDeletionService
    ) {
        self.bookRepository = bookRepository
        self.groupRepository = groupRepository
        self.appSettingsStore = appSettingsStore
        self.deletionService = deletionService
    }

    func refresh() {
        refreshGroups()
        do {
            let books = try bookRepository.fetchBookshelfItems(
                sortMode: appSettingsStore.bookshelfSortMode,
                groupFilter: selectedGroupFilter,
                searchText: searchText
            )
            items.send(books.isEmpty ? [.emptyState] : books.map(Item.book))
        } catch {
            items.send([.emptyState])
        }
    }

    func selectGroupFilter(_ filter: BookshelfGroupFilter) {
        selectedGroupFilter = filter
        refresh()
    }

    func updateSearchText(_ text: String) {
        searchText = text
        refresh()
    }

    func setSortMode(_ sortMode: BookshelfSortMode) {
        appSettingsStore.bookshelfSortMode = sortMode
        refresh()
    }

    func createGroup(name: String) throws {
        _ = try groupRepository.createGroup(name: name)
        refresh()
    }

    func renameGroup(id: UUID, name: String) throws {
        try groupRepository.renameGroup(id: id, name: name)
        refresh()
    }

    func deleteGroup(id: UUID) throws {
        try groupRepository.deleteGroup(id: id)
        if selectedGroupFilter == .group(id) {
            selectedGroupFilter = .all
        }
        refresh()
    }

    func moveBooks(_ bookIDs: [UUID], toGroupID groupID: UUID?) throws {
        try bookRepository.moveBooks(bookIDs, toGroupID: groupID)
        refresh()
    }

    func deleteBooks(_ bookIDs: [UUID]) async throws {
        try await deletionService.deleteBooks(bookIDs)
    }

    func recentBooks(limit: Int = 20) throws -> [BookshelfBookItem] {
        try bookRepository.fetchRecentBooks(limit: limit)
    }

    func searchBooks(query: String) throws -> [BookshelfBookItem] {
        try bookRepository.fetchBookshelfItems(
            sortMode: appSettingsStore.bookshelfSortMode,
            groupFilter: .all,
            searchText: query
        )
    }

    var currentSortMode: BookshelfSortMode {
        appSettingsStore.bookshelfSortMode
    }

    var currentGroupFilter: BookshelfGroupFilter {
        selectedGroupFilter
    }

    var searchHistory: [String] {
        appSettingsStore.bookshelfSearchHistory
    }

    func rememberSearch(_ query: String) {
        appSettingsStore.rememberBookshelfSearch(query)
    }

    func clearSearchHistory() {
        appSettingsStore.clearBookshelfSearchHistory()
    }

    private func refreshGroups() {
        do {
            groupList.send(try groupRepository.fetchGroupList())
        } catch {
            groupList.send(BookGroupList(totalBookCount: 0, ungroupedBookCount: 0, groups: []))
        }
    }
}
