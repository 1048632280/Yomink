import Foundation

enum TextDecoderError: Error {
    case unsupportedEncoding
    case undecodableWindow
}

struct TextDecoder {
    func detectEncoding(from sample: Data) -> TextEncoding {
        if sample.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8
        }
        if sample.starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian
        }
        if sample.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }
        if String(data: sample, encoding: .utf8) != nil {
            return .utf8
        }
        return .gb18030
    }

    func decodeWindow(data: Data, encoding: TextEncoding) throws -> String {
        guard let text = String(data: data, encoding: encoding.stringEncoding) else {
            throw TextDecoderError.undecodableWindow
        }
        return text
    }
}

