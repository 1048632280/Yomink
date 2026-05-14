import Foundation

struct ReaderSessionState: Hashable, Sendable {
    let bookID: UUID
    let currentPageIndex: Int
    let residentPageCount: Int
    let startByteOffset: UInt64
    let endByteOffset: UInt64
    let fileSize: UInt64
    let isLoadingNextPage: Bool
    let didReachEndOfBook: Bool

    var progressFraction: Double {
        guard fileSize > 0 else {
            return 0
        }

        let fraction = Double(startByteOffset) / Double(fileSize)
        return min(1, max(0, fraction))
    }

    var progressPercentText: String {
        String(format: "%.1f%%", progressFraction * 100)
    }
}

