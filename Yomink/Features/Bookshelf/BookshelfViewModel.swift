import Combine
import Foundation

final class BookshelfViewModel {
    enum Item: Hashable {
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
        items.send([.emptyState])
    }
}

