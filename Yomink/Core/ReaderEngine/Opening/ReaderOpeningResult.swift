import Foundation

struct ReaderOpeningResult: Hashable, Sendable {
    let book: BookRecord
    let page: ReaderPage
    let progress: ReadingProgress
}

