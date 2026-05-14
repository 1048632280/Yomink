import Foundation

final class ReadingProgressStore: @unchecked Sendable {
    private let databaseManager: DatabaseManager
    private var pendingProgress: ReadingProgress?

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func remember(_ progress: ReadingProgress) {
        pendingProgress = progress
    }

    func progress(for bookID: UUID) throws -> ReadingProgress? {
        try databaseManager.readProgress(bookID: bookID)
    }

    func flushPendingProgress() {
        guard let progress = pendingProgress else {
            return
        }
        pendingProgress = nil
        databaseManager.writeProgress(progress)
    }
}
