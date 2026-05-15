import Foundation

final class ReadingChapterService: @unchecked Sendable {
    private static let batchSize = 32

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
        guard !suspendedBookIDs.contains(bookID) else {
            lock.unlock()
            return
        }
        if parsingTasks[bookID] != nil {
            lock.unlock()
            return
        }

        let task = Task.detached(priority: .utility) { [self] in
            defer {
                finishParsing(bookID: bookID)
            }

            do {
                guard let book = try bookRepository.fetchBook(id: bookID) else {
                    return
                }
                guard try !chapterRepository.isParsingCompleted(bookID: bookID) else {
                    return
                }
                try await parseChapters(for: book)
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Chapter parsing failed: \(error)")
            }
        }
        parsingTasks[bookID] = task
        lock.unlock()
    }

    func chapters(bookID: UUID) async throws -> [ReadingChapter] {
        try await Task.detached(priority: .userInitiated) { [chapterRepository] in
            try chapterRepository.fetchChapters(bookID: bookID)
        }.value
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

    private func parseChapters(for book: BookRecord) async throws {
        try chapterRepository.deleteChapters(bookID: book.id)
        try chapterRepository.clearParsingState(bookID: book.id)
        var didCompleteParsing = false
        defer {
            if !didCompleteParsing {
                try? chapterRepository.deleteChapters(bookID: book.id)
                try? chapterRepository.clearParsingState(bookID: book.id)
            }
        }

        let mapping = try BookFileMapping(fileURL: book.fileURL)
        var windowStartByteOffset: UInt64 = 0
        var sortIndex = 0
        var pendingChapters: [ReadingChapter] = []
        var seenChapters: [ChapterCandidate] = []

        while windowStartByteOffset < mapping.fileSize {
            if Task.isCancelled {
                return
            }

            let windowEndByteOffset = min(
                mapping.fileSize,
                windowStartByteOffset + ChapterParser.maximumWindowLength
            )
            let windowData = try mapping.bytes(in: windowStartByteOffset..<windowEndByteOffset)
            let candidates = try parser.parseCandidates(
                in: windowData,
                byteRange: windowStartByteOffset..<windowEndByteOffset,
                encoding: book.encoding
            )

            for candidate in candidates where !Self.hasSeen(candidate, in: seenChapters) {
                seenChapters.append(candidate)
                pendingChapters.append(
                    ReadingChapter(
                        bookID: book.id,
                        title: candidate.title,
                        byteOffset: candidate.byteOffset,
                        sortIndex: sortIndex
                    )
                )
                sortIndex += 1
            }

            if pendingChapters.count >= Self.batchSize {
                try chapterRepository.insertChapters(pendingChapters)
                pendingChapters.removeAll(keepingCapacity: true)
            }

            guard windowEndByteOffset < mapping.fileSize else {
                break
            }

            let nextStart = windowEndByteOffset - min(
                ChapterParser.overlapLength,
                windowEndByteOffset - windowStartByteOffset
            )
            windowStartByteOffset = nextStart > windowStartByteOffset ? nextStart : windowEndByteOffset

            // Catalog parsing is useful but non-urgent; this cooperative pause keeps
            // long TXT scans from keeping CPU warm during quiet reading.
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        try chapterRepository.insertChapters(pendingChapters)
        try chapterRepository.markParsingCompleted(bookID: book.id)
        didCompleteParsing = true
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
