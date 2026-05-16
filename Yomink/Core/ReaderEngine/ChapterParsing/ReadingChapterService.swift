import Combine
import Foundation

final class ReadingChapterService: @unchecked Sendable {
    private static let parseYieldDelayNanoseconds: UInt64 = 4_000_000

    private let chapterUpdatesSubject = PassthroughSubject<UUID, Never>()
    var chapterUpdates: AnyPublisher<UUID, Never> {
        chapterUpdatesSubject.eraseToAnyPublisher()
    }

    private let bookRepository: BookRepository
    private let chapterRepository: ChapterRepository
    private let parser: ChapterParser
    private let lock = NSLock()
    private var parsingTasks: [UUID: Task<Void, Never>] = [:]
    private var suspendedBookIDs: Set<UUID> = []

    init(
        bookRepository: BookRepository,
        chapterRepository: ChapterRepository,
        parser: ChapterParser
    ) {
        self.bookRepository = bookRepository
        self.chapterRepository = chapterRepository
        self.parser = parser
    }

    func scheduleParsing(bookID: UUID) {
        lock.lock()
        guard !suspendedBookIDs.contains(bookID),
              parsingTasks[bookID] == nil else {
            lock.unlock()
            return
        }

        let task = Task.detached(priority: .utility) { [self] in
            defer {
                finishParsing(bookID: bookID)
            }
            await parseChapters(bookID: bookID)
        }
        parsingTasks[bookID] = task
        lock.unlock()
    }

    func catalogSnapshot(
        bookID: UUID,
        scheduleIfNeeded: Bool = true,
        priority: TaskPriority = .userInitiated
    ) async throws -> ChapterCatalogSnapshot {
        let snapshot = try await Task.detached(priority: priority) { [chapterRepository] in
            try chapterRepository.fetchCatalogSnapshot(bookID: bookID)
        }.value

        if scheduleIfNeeded, Self.shouldScheduleParsing(for: snapshot.status) {
            scheduleParsing(bookID: bookID)
        }

        return snapshot
    }

    func chapters(bookID: UUID, priority: TaskPriority = .userInitiated) async throws -> [ReadingChapter] {
        let snapshot = try await catalogSnapshot(
            bookID: bookID,
            scheduleIfNeeded: false,
            priority: priority
        )
        return snapshot.chapters
    }

    func cancelParsing(bookID: UUID) {
        lock.lock()
        let task = parsingTasks.removeValue(forKey: bookID)
        lock.unlock()
        task?.cancel()
    }

    func pauseParsing(bookID: UUID) {
        lock.lock()
        suspendedBookIDs.insert(bookID)
        let task = parsingTasks.removeValue(forKey: bookID)
        lock.unlock()
        task?.cancel()
    }

    func resumeParsing(bookID: UUID) {
        lock.lock()
        suspendedBookIDs.remove(bookID)
        lock.unlock()
        scheduleParsing(bookID: bookID)
    }

    private func parseChapters(bookID: UUID) async {
        var latestScannedByteOffset: UInt64 = 0
        var fileSize: UInt64 = 0
        var nextSortIndex = 0

        do {
            guard let book = try bookRepository.fetchBook(id: bookID) else {
                return
            }

            var snapshot = try chapterRepository.fetchCatalogSnapshot(bookID: bookID)
            if book.fileSize == 0 {
                if snapshot.state?.isCompleted == true {
                    return
                }
                try chapterRepository.updateParsingState(
                    bookID: bookID,
                    scannedUntilByteOffset: 0,
                    fileSize: 0,
                    nextSortIndex: try chapterRepository.nextSortIndex(bookID: bookID),
                    completedAt: Date(),
                    failureReason: nil
                )
                notifyChapterUpdate(bookID: bookID)
                return
            }

            let mapping = try BookFileMapping(fileURL: book.fileURL)
            fileSize = mapping.fileSize

            if let state = snapshot.state,
               state.fileSize > 0,
               state.fileSize != fileSize {
                try chapterRepository.resetParsingData(bookID: bookID)
                snapshot = ChapterCatalogSnapshot(chapters: [], state: nil)
            }

            if let state = snapshot.state,
               state.isCompleted,
               (state.fileSize == fileSize || state.fileSize == 0) {
                return
            }

            latestScannedByteOffset = min(snapshot.state?.scannedUntilByteOffset ?? 0, fileSize)
            nextSortIndex = max(snapshot.state?.nextSortIndex ?? 0, try chapterRepository.nextSortIndex(bookID: bookID))
            var recentCandidates = snapshot.chapters.suffix(12).map {
                ChapterCandidate(title: $0.title, byteOffset: $0.byteOffset)
            }
            let isRetryingFailure: Bool = {
                if case .failed(_) = snapshot.status {
                    return true
                }
                return false
            }()

            if snapshot.state == nil || isRetryingFailure {
                try chapterRepository.updateParsingState(
                    bookID: bookID,
                    scannedUntilByteOffset: latestScannedByteOffset,
                    fileSize: fileSize,
                    nextSortIndex: nextSortIndex,
                    completedAt: nil,
                    failureReason: nil
                )
                if isRetryingFailure {
                    notifyChapterUpdate(bookID: bookID)
                }
            }

            var windowStartByteOffset = latestScannedByteOffset > ChapterParser.overlapLength
                ? latestScannedByteOffset - ChapterParser.overlapLength
                : 0

            while windowStartByteOffset < fileSize {
                try Task.checkCancellation()

                let windowEndByteOffset = min(
                    fileSize,
                    windowStartByteOffset + ChapterParser.maximumWindowLength
                )
                let windowData = try mapping.bytes(in: windowStartByteOffset..<windowEndByteOffset)
                let candidates = (try? parser.parseCandidates(
                    in: windowData,
                    byteRange: windowStartByteOffset..<windowEndByteOffset,
                    encoding: book.encoding,
                    isFinalWindow: windowEndByteOffset >= fileSize
                )) ?? []

                var pendingChapters: [ReadingChapter] = []
                pendingChapters.reserveCapacity(candidates.count)
                for candidate in candidates
                    where candidate.byteOffset < fileSize
                        && !Self.hasSeen(candidate, in: recentCandidates) {
                    pendingChapters.append(
                        ReadingChapter(
                            bookID: bookID,
                            title: candidate.title,
                            byteOffset: candidate.byteOffset,
                            sortIndex: nextSortIndex
                        )
                    )
                    nextSortIndex += 1
                    recentCandidates.append(candidate)
                    if recentCandidates.count > 24 {
                        recentCandidates.removeFirst(recentCandidates.count - 24)
                    }
                }

                latestScannedByteOffset = windowEndByteOffset
                let didComplete = latestScannedByteOffset >= fileSize
                let state = ChapterParseState(
                    bookID: bookID,
                    scannedUntilByteOffset: latestScannedByteOffset,
                    fileSize: fileSize,
                    nextSortIndex: nextSortIndex,
                    updatedAt: Date(),
                    completedAt: didComplete ? Date() : nil,
                    failureReason: nil
                )
                nextSortIndex = try chapterRepository.insertChapters(pendingChapters, state: state)

                if !pendingChapters.isEmpty || didComplete {
                    notifyChapterUpdate(bookID: bookID)
                }

                guard !didComplete else {
                    break
                }

                let nextStart = windowEndByteOffset - min(
                    ChapterParser.overlapLength,
                    windowEndByteOffset - windowStartByteOffset
                )
                windowStartByteOffset = nextStart > windowStartByteOffset
                    ? nextStart
                    : windowEndByteOffset

                // Keep parsing cooperative so catalog work does not compete with paging.
                try await Task.sleep(nanoseconds: Self.parseYieldDelayNanoseconds)
            }
        } catch is CancellationError {
            return
        } catch {
            try? chapterRepository.updateParsingState(
                bookID: bookID,
                scannedUntilByteOffset: latestScannedByteOffset,
                fileSize: fileSize,
                nextSortIndex: nextSortIndex,
                completedAt: nil,
                failureReason: String(describing: error)
            )
            notifyChapterUpdate(bookID: bookID)
        }
    }

    private func notifyChapterUpdate(bookID: UUID) {
        DispatchQueue.main.async { [self] in
            chapterUpdatesSubject.send(bookID)
        }
    }

    private static func shouldScheduleParsing(for status: ChapterParseStatus) -> Bool {
        switch status {
        case .notStarted, .parsing, .failed:
            return true
        case .completed:
            return false
        }
    }

    private static func hasSeen(_ candidate: ChapterCandidate, in candidates: [ChapterCandidate]) -> Bool {
        candidates.contains { existingCandidate in
            let distance = existingCandidate.byteOffset > candidate.byteOffset
                ? existingCandidate.byteOffset - candidate.byteOffset
                : candidate.byteOffset - existingCandidate.byteOffset
            return existingCandidate.title == candidate.title
                && distance <= ChapterParser.overlapLength
        }
    }

    private func finishParsing(bookID: UUID) {
        lock.lock()
        parsingTasks.removeValue(forKey: bookID)
        lock.unlock()
    }
}
