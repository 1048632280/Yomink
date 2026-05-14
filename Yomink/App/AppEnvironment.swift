import Foundation

struct AppEnvironment {
    let databaseManager: DatabaseManager
    let bookRepository: BookRepository
    let appSettingsStore: AppSettingsStore
    let readingSettingsStore: ReadingSettingsStore
    let readingProgressStore: ReadingProgressStore
    let searchIndexService: SearchIndexService
    let bookImportService: BookImportService
    let readerOpeningService: ReaderOpeningService
    let readerPagingService: ReaderPagingService

    static func makeDefault() -> AppEnvironment {
        let databaseManager = DatabaseManager.defaultDatabase()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let appSettingsStore = AppSettingsStore()
        let readingSettingsStore = ReadingSettingsStore()
        let readingProgressStore = ReadingProgressStore(databaseManager: databaseManager)
        let searchIndexService = SearchIndexService(databaseManager: databaseManager)
        let readerPageCache = ReaderPageCache()
        let bookImportService = BookImportService(bookRepository: bookRepository)
        let readerOpeningService = ReaderOpeningService(
            bookRepository: bookRepository,
            progressStore: readingProgressStore
        )
        let readerPagingService = ReaderPagingService(
            bookRepository: bookRepository,
            pageCache: readerPageCache
        )

        return AppEnvironment(
            databaseManager: databaseManager,
            bookRepository: bookRepository,
            appSettingsStore: appSettingsStore,
            readingSettingsStore: readingSettingsStore,
            readingProgressStore: readingProgressStore,
            searchIndexService: searchIndexService,
            bookImportService: bookImportService,
            readerOpeningService: readerOpeningService,
            readerPagingService: readerPagingService
        )
    }
}
