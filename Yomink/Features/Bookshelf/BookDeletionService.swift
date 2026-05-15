import Foundation

final class BookDeletionService: @unchecked Sendable {
    private let bookRepository: BookRepository
    private let searchIndexService: SearchIndexService
    private let pagingService: ReaderPagingService
    private let fileManager: FileManager

    init(
        bookRepository: BookRepository,
        searchIndexService: SearchIndexService,
        pagingService: ReaderPagingService,
        fileManager: FileManager = .default
    ) {
        self.bookRepository = bookRepository
        self.searchIndexService = searchIndexService
        self.pagingService = pagingService
        self.fileManager = fileManager
    }

    func deleteBooks(_ bookIDs: [UUID]) async throws {
        for bookID in bookIDs {
            searchIndexService.cancelIndexing(bookID: bookID)
        }

        try await Task.detached(priority: .utility) { [self] in
            let books = try bookRepository.deleteBooks(bookIDs)
            for book in books {
                if fileManager.fileExists(atPath: book.filePath) {
                    try fileManager.removeItem(at: book.fileURL)
                }
            }
        }.value
        pagingService.removeCachedPages()
    }
}
