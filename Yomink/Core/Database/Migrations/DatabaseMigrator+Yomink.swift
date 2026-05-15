import Foundation
import GRDB

extension DatabaseMigrator {
    static var yominkMigrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createBooks") { database in
            try database.create(table: "books", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("author", .text)
                table.column("filePath", .text).notNull()
                table.column("encoding", .text).notNull()
                table.column("fileSize", .integer).notNull()
                table.column("importedAt", .double).notNull()
                table.column("lastReadAt", .double)
            }
        }

        migrator.registerMigration("createReadingProgress") { database in
            try database.create(table: "readingProgress", ifNotExists: true) { table in
                table.column("bookID", .text).primaryKey()
                table.column("byteOffset", .integer).notNull()
                table.column("updatedAt", .double).notNull()
            }
        }

        migrator.registerMigration("createSettings") { database in
            try database.create(table: "settings", ifNotExists: true) { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("createBookmarks") { database in
            try database.create(table: "bookmarks", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("bookID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("byteOffset", .integer).notNull()
                table.column("createdAt", .double).notNull()
            }
            try database.execute(
                sql: "CREATE INDEX IF NOT EXISTS bookmarks_on_bookID ON bookmarks(bookID)"
            )
        }

        migrator.registerMigration("createChapters") { database in
            try database.create(table: "chapters", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("bookID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("byteOffset", .integer).notNull()
                table.column("sortIndex", .integer).notNull()
                table.column("createdAt", .double).notNull()
            }
            try database.execute(
                sql: "CREATE INDEX IF NOT EXISTS chapters_on_bookID ON chapters(bookID)"
            )
            try database.execute(
                sql: "CREATE UNIQUE INDEX IF NOT EXISTS chapters_on_bookID_byteOffset ON chapters(bookID, byteOffset)"
            )
        }

        migrator.registerMigration("createChapterParseStates") { database in
            try database.create(table: "chapterParseStates", ifNotExists: true) { table in
                table.column("bookID", .text).primaryKey()
                table.column("completedAt", .double).notNull()
            }
        }

        migrator.registerMigration("deduplicateBookmarks") { database in
            try database.execute(
                sql: """
                DELETE FROM bookmarks
                WHERE EXISTS (
                    SELECT 1
                    FROM bookmarks AS kept
                    WHERE kept.bookID = bookmarks.bookID
                        AND kept.byteOffset = bookmarks.byteOffset
                        AND (
                            kept.createdAt < bookmarks.createdAt
                            OR (kept.createdAt = bookmarks.createdAt AND kept.id < bookmarks.id)
                        )
                )
                """
            )
            try database.execute(
                sql: "CREATE UNIQUE INDEX IF NOT EXISTS bookmarks_on_bookID_byteOffset ON bookmarks(bookID, byteOffset)"
            )
        }

        migrator.registerMigration("createBookSearchIndex") { database in
            try database.execute(
                sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS bookSearchIndex USING fts5(
                    bookID UNINDEXED,
                    chunkIndex UNINDEXED,
                    startByteOffset UNINDEXED,
                    endByteOffset UNINDEXED,
                    content,
                    tokenize = 'trigram'
                )
                """
            )
            try database.create(table: "bookSearchIndexStates", ifNotExists: true) { table in
                table.column("bookID", .text).primaryKey()
                table.column("indexedUntilByteOffset", .integer).notNull()
                table.column("fileSize", .integer).notNull()
                table.column("updatedAt", .double).notNull()
                table.column("completedAt", .double)
            }
        }

        return migrator
    }
}
