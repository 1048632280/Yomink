import Foundation

enum BookFileMappingError: Error {
    case emptyFile
    case invalidRange
    case mappingUnavailable
}

final class BookFileMapping {
    static let maximumWindowLength: UInt64 = 1 * 1024 * 1024

    let fileURL: URL
    let fileSize: UInt64

    private let data: Data

    init(fileURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize > 0 else {
            throw BookFileMappingError.emptyFile
        }

        self.fileURL = fileURL
        self.fileSize = fileSize

        // The mapped Data keeps mmap ownership local and avoids copying the whole TXT into heap memory.
        self.data = try Data(contentsOf: fileURL, options: [.alwaysMapped])
    }

    func bytes(in byteRange: Range<UInt64>) throws -> Data {
        guard byteRange.lowerBound <= byteRange.upperBound,
              byteRange.upperBound <= fileSize else {
            throw BookFileMappingError.invalidRange
        }
        guard byteRange.upperBound - byteRange.lowerBound <= Self.maximumWindowLength else {
            throw BookFileMappingError.invalidRange
        }

        let lowerBound = Int(byteRange.lowerBound)
        let upperBound = Int(byteRange.upperBound)
        return data.subdata(in: lowerBound..<upperBound)
    }
}
