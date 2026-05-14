import Combine
import Foundation

final class BookshelfViewModel {
    enum Item: Hashable {
        case book(BookRecord)
        case emptyState
    }

    let title = "Yomink"
    let items = CurrentValueSubject<[Item], Never>([.emptyState])

    private let bookRepository: BookRepository
    private let appSettingsStore: AppSettingsStore

    init(bookRepository: BookRepository, appSettingsStore: AppSettingsStore) {
        self.bookRepository = bookRepository
        self.appSettingsStore = appSettingsStore
    }

    func refresh() {
        do {
            let books = try bookRepository.fetchBooks(sortMode: appSettingsStore.bookshelfSortMode)
            items.send(books.isEmpty ? [.emptyState] : books.map(Item.book))
        } catch {
            items.send([.emptyState])
        }
    }
}
