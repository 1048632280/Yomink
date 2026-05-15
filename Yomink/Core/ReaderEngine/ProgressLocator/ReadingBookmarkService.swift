import Foundation

final class ReadingBookmarkService: @unchecked Sendable {
    private let repository: BookmarkRepository

    init(repository: BookmarkRepository) {
        self.repository = repository
    }

    func addBookmark(bookID: UUID, page: ReaderPage) async throws -> ReadingBookmarkAddResult {
        let title = Self.makeBookmarkTitle(page: page)
        let bookmark = ReadingBookmark(
            bookID: bookID,
            title: title,
            byteOffset: page.startByteOffset
        )
        return try await Task.detached(priority: .utility) { [repository] in
            try repository.insertIfNeeded(bookmark)
        }.value
    }

    func bookmarks(bookID: UUID) async throws -> [ReadingBookmark] {
        try await Task.detached(priority: .utility) { [repository] in
            try repository.fetchBookmarks(bookID: bookID)
        }.value
    }

    func deleteBookmark(_ bookmark: ReadingBookmark) async throws {
        try await Task.detached(priority: .utility) { [repository] in
            try repository.deleteBookmark(id: bookmark.id, bookID: bookmark.bookID)
        }.value
    }

    private static func makeBookmarkTitle(page: ReaderPage) -> String {
        let collapsedText = page.text.split(whereSeparator: \.isNewline)
            .lazy
            .map { line in
                String(line).stableBookmarkLine()
            }
            .first { !$0.isEmpty }
            ?? "\u{4F4D}\u{7F6E} \(page.startByteOffset)"

        if collapsedText.count <= 32 {
            return collapsedText
        }
        return String(collapsedText.prefix(32))
    }
}

private extension String {
    func stableBookmarkLine() -> String {
        var result = ""
        var didAppendWhitespace = false

        for scalar in unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !result.isEmpty {
                    didAppendWhitespace = true
                }
                continue
            }

            if didAppendWhitespace {
                result.append(" ")
                didAppendWhitespace = false
            }
            result.append(String(scalar))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
