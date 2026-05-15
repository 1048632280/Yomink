import Foundation

struct AppEnvironment {
    let databaseManager: DatabaseManager
    let bookRepository: BookRepository
    let bookGroupRepository: BookGroupRepository
    let appSettingsStore: AppSettingsStore
    let readingSettingsStore: ReadingSettingsStore
    let readingProgressStore: ReadingProgressStore
    let searchIndexService: SearchIndexService
    let bookImportService: BookImportService
    let readingBookmarkService: ReadingBookmarkService
    let readingChapterService: ReadingChapterService
    let readerOpeningService: ReaderOpeningService
    let readerPagingService: ReaderPagingService

    static func makeDefault() -> AppEnvironment {
        let databaseManager = DatabaseManager.defaultDatabase()
        let bookRepository = BookRepository(databaseManager: databaseManager)
        let bookGroupRepository = BookGroupRepository(databaseManager: databaseManager)
        let bookmarkRepository = BookmarkRepository(databaseManager: databaseManager)
        let chapterRepository = ChapterRepository(databaseManager: databaseManager)
        let appSettingsStore = AppSettingsStore()
        let readingSettingsStore = ReadingSettingsStore()
        let readingProgressStore = ReadingProgressStore(databaseManager: databaseManager)
        let searchIndexService = SearchIndexService(
            databaseManager: databaseManager,
            bookRepository: bookRepository
        )
        let readerPageCache = ReaderPageCache()
        let bookImportService = BookImportService(bookRepository: bookRepository)
        let readingBookmarkService = ReadingBookmarkService(repository: bookmarkRepository)
        let readingChapterService = ReadingChapterService(
            bookRepository: bookRepository,
            chapterRepository: chapterRepository,
            parser: ChapterParser()
        )
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
            bookGroupRepository: bookGroupRepository,
            appSettingsStore: appSettingsStore,
            readingSettingsStore: readingSettingsStore,
            readingProgressStore: readingProgressStore,
            searchIndexService: searchIndexService,
            bookImportService: bookImportService,
            readingBookmarkService: readingBookmarkService,
            readingChapterService: readingChapterService,
            readerOpeningService: readerOpeningService,
            readerPagingService: readerPagingService
        )
    }
}
