import Foundation

enum BookImportError: Error, Sendable {
    case emptyFile
    case missingSample
    case duplicateBook(BookImportDuplicate)
}

enum BookImportDuplicateResolution: Sendable, Equatable {
    case reject
    case createCopy
}

struct BookImportDuplicate: Sendable {
    let existingBook: BookRecord
    let importedTitle: String

    var copyTitle: String {
        "\(importedTitle)-\u{526F}\u{672C}"
    }
}

final class BookImportService: @unchecked Sendable {
    static let sampleLength = 64 * 1024

    private let bookRepository: BookRepository
    private let fileManager: FileManager

    init(bookRepository: BookRepository, fileManager: FileManager = .default) {
        self.bookRepository = bookRepository
        self.fileManager = fileManager
    }

    func importBook(
        from sourceURL: URL,
        duplicateResolution: BookImportDuplicateResolution = .reject
    ) async throws -> BookRecord {
        try await Task.detached(priority: .userInitiated) { [self] in
            let source = try Self.inspectSource(from: sourceURL, fileManager: fileManager)
            let duplicate = try Self.findDuplicate(
                for: source,
                candidates: bookRepository.fetchBooks(fileSize: source.fileSize),
                fileManager: fileManager
            )
            if let duplicate,
               duplicateResolution == .reject {
                throw BookImportError.duplicateBook(
                    BookImportDuplicate(
                        existingBook: duplicate,
                        importedTitle: source.title
                    )
                )
            }

            let preparedBook = try Self.prepareImport(
                from: sourceURL,
                source: source,
                titleOverride: duplicate == nil ? nil : "\(source.title)-\u{526F}\u{672C}",
                fileManager: fileManager
            )
            return try bookRepository.insertImportedBook(preparedBook)
        }.value
    }

    private static func inspectSource(from sourceURL: URL, fileManager: FileManager) throws -> SourceBookImport {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize > 0 else {
            throw BookImportError.emptyFile
        }

        let sample = try readSample(from: sourceURL)
        guard !sample.isEmpty else {
            throw BookImportError.missingSample
        }
        let tailSample = try readTailSample(from: sourceURL, fileSize: fileSize)

        let decoder = TextDecoder()
        let encoding = decoder.detectEncoding(from: sample)
        let title = inferTitle(sourceURL: sourceURL, sample: sample, encoding: encoding)

        return SourceBookImport(
            title: title,
            encoding: encoding,
            fileSize: fileSize,
            headSample: sample,
            tailSample: tailSample
        )
    }

    private static func prepareImport(
        from sourceURL: URL,
        source: SourceBookImport,
        titleOverride: String?,
        fileManager: FileManager
    ) throws -> BookRecord {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let id = UUID()
        let destinationURL = try destinationURL(for: id, fileManager: fileManager)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return BookRecord(
            id: id,
            title: titleOverride ?? source.title,
            author: nil,
            groupID: nil,
            filePath: destinationURL.path,
            encoding: source.encoding,
            fileSize: source.fileSize,
            importedAt: Date(),
            lastReadAt: nil
        )
    }

    private static func findDuplicate(
        for source: SourceBookImport,
        candidates: [BookRecord],
        fileManager: FileManager
    ) throws -> BookRecord? {
        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.filePath) else {
                continue
            }

            let candidateURL = candidate.fileURL
            guard let candidateHeadSample = try? readSample(from: candidateURL),
                  candidateHeadSample == source.headSample,
                  let candidateTailSample = try? readTailSample(from: candidateURL, fileSize: candidate.fileSize),
                  candidateTailSample == source.tailSample else {
                continue
            }
            return candidate
        }

        return nil
    }

    private static func readSample(from sourceURL: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? handle.close()
        }
        return try handle.read(upToCount: sampleLength) ?? Data()
    }

    private static func readTailSample(from sourceURL: URL, fileSize: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? handle.close()
        }

        let offset = fileSize > UInt64(sampleLength) ? fileSize - UInt64(sampleLength) : 0
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: sampleLength) ?? Data()
    }

    private static func destinationURL(for id: UUID, fileManager: FileManager) throws -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yomink", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(id.uuidString).appendingPathExtension("txt")
    }

    private static func inferTitle(sourceURL: URL, sample: Data, encoding: TextEncoding) -> String {
        if let text = try? TextDecoder().decodeWindow(data: sample, encoding: encoding) {
            let title = text
                .split(whereSeparator: \.isNewline)
                .lazy
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let title, title.count <= 80 {
                return title
            }
        }

        return sourceURL.deletingPathExtension().lastPathComponent
    }
}

private struct SourceBookImport {
    let title: String
    let encoding: TextEncoding
    let fileSize: UInt64
    let headSample: Data
    let tailSample: Data
}
