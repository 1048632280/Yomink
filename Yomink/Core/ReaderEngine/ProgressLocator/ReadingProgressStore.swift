import Foundation

final class ReadingProgressStore {
    private let databaseManager: DatabaseManager
    private var pendingProgress: ReadingProgress?

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func remember(_ progress: ReadingProgress) {
        pendingProgress = progress
    }

    func flushPendingProgress() {
        guard let progress = pendingProgress else {
            return
        }
        pendingProgress = nil
        databaseManager.writeProgress(progress)
    }
}

