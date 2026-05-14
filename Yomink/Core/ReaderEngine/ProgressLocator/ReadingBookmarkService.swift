import Foundation

final class ReadingBookmarkService: @unchecked Sendable {
    private let repository: BookmarkRepository

    init(repository: BookmarkRepository) {
        self.repository = repository
    }

    func addBookmark(bookID: UUID, page: ReaderPage) async throws -> ReadingBookmark {
        let title = Self.makeBookmarkTitle(page: page)
        let bookmark = ReadingBookmark(
            bookID: bookID,
            title: title,
            byteOffset: page.startByteOffset
        )
        return try await Task.detached(priority: .utility) { [repository] in
            try repository.insert(bookmark)
        }.value
    }

    func bookmarks(bookID: UUID) async throws -> [ReadingBookmark] {
        try await Task.detached(priority: .utility) { [repository] in
            try repository.fetchBookmarks(bookID: bookID)
        }.value
    }

    private static func makeBookmarkTitle(page: ReaderPage) -> String {
        let collapsedText = page.text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "\u{4E66}\u{7B7E}"

        if collapsedText.count <= 40 {
            return collapsedText
        }
        return String(collapsedText.prefix(40))
    }
}
