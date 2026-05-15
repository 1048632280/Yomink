import Foundation

enum TextDecoderError: Error {
    case unsupportedEncoding
    case undecodableWindow
}

struct DecodedTextWindow: Sendable {
    let text: String
    let trimmedPrefixByteCount: UInt64
    let trimmedSuffixByteCount: UInt64
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

    func decodeBoundedWindow(data: Data, encoding: TextEncoding) throws -> DecodedTextWindow {
        if let text = String(data: data, encoding: encoding.stringEncoding) {
            return DecodedTextWindow(
                text: text,
                trimmedPrefixByteCount: 0,
                trimmedSuffixByteCount: 0
            )
        }

        let maximumTrimLength = min(4, data.count)
        for prefixLength in 0...maximumTrimLength {
            for suffixLength in 0...maximumTrimLength {
                guard prefixLength + suffixLength < data.count else {
                    continue
                }

                let lowerBound = data.startIndex + prefixLength
                let upperBound = data.endIndex - suffixLength
                let trimmedData = Data(data[lowerBound..<upperBound])
                if let text = String(data: trimmedData, encoding: encoding.stringEncoding) {
                    return DecodedTextWindow(
                        text: text,
                        trimmedPrefixByteCount: UInt64(prefixLength),
                        trimmedSuffixByteCount: UInt64(suffixLength)
                    )
                }
            }
        }

        throw TextDecoderError.undecodableWindow
    }
}
