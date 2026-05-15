import Foundation

enum BookImportError: Error {
    case emptyFile
    case missingSample
}

final class BookImportService: @unchecked Sendable {
    static let sampleLength = 64 * 1024

    private let bookRepository: BookRepository
    private let fileManager: FileManager

    init(bookRepository: BookRepository, fileManager: FileManager = .default) {
        self.bookRepository = bookRepository
        self.fileManager = fileManager
    }

    func importBook(from sourceURL: URL) async throws -> BookRecord {
        try await Task.detached(priority: .userInitiated) { [self] in
            let preparedBook = try Self.prepareImport(from: sourceURL, fileManager: fileManager)
            return try bookRepository.insertImportedBook(preparedBook)
        }.value
    }

    private static func prepareImport(from sourceURL: URL, fileManager: FileManager) throws -> BookRecord {
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

        let decoder = TextDecoder()
        let encoding = decoder.detectEncoding(from: sample)
        let id = UUID()
        let destinationURL = try destinationURL(for: id, fileManager: fileManager)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return BookRecord(
            id: id,
            title: inferTitle(sourceURL: sourceURL, sample: sample, encoding: encoding),
            author: nil,
            groupID: nil,
            filePath: destinationURL.path,
            encoding: encoding,
            fileSize: fileSize,
            importedAt: Date(),
            lastReadAt: nil
        )
    }

    private static func readSample(from sourceURL: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? handle.close()
        }
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
