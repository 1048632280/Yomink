import Foundation

struct AppEnvironment {
    let databaseManager: DatabaseManager
    let bookRepository: BookRepository
    let appSettingsStore: AppSettingsStore
    let readingSettingsStore: ReadingSettingsStore
    let readingProgressStore: ReadingProgressStore
    let searchIndexService: SearchIndexService

    static func makeDefault() -> AppEnvironment {
        let databaseManager = DatabaseManager.defaultDatabase()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let appSettingsStore = AppSettingsStore()
        let readingSettingsStore = ReadingSettingsStore()
        let readingProgressStore = ReadingProgressStore(databaseManager: databaseManager)
        let searchIndexService = SearchIndexService(databaseManager: databaseManager)

        return AppEnvironment(
            databaseManager: databaseManager,
            bookRepository: bookRepository,
            appSettingsStore: appSettingsStore,
            readingSettingsStore: readingSettingsStore,
            readingProgressStore: readingProgressStore,
            searchIndexService: searchIndexService
        )
    }
}

