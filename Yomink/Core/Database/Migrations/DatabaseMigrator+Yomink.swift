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

        return migrator
    }
}

