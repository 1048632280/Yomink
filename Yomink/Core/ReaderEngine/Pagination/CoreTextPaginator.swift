import CoreGraphics
import CoreText
import Foundation

enum PaginationError: Error {
    case emptyWindow
    case invalidLayout
    case windowTooLarge
}

struct CoreTextPaginator {
    static let maximumUTF16Length = 120_000

    func paginateFirstPage(
        window: TextWindow,
        layout: ReadingLayout,
        bookID: UUID
    ) throws -> PageByteRange {
        guard !Thread.isMainThread else {
            assertionFailure("CoreText pagination must not run on the main thread.")
            throw PaginationError.invalidLayout
        }
        guard !window.text.isEmpty else {
            throw PaginationError.emptyWindow
        }
        guard window.text.utf16.count <= Self.maximumUTF16Length else {
            throw PaginationError.windowTooLarge
        }

        let attributedString = NSAttributedString(
            string: window.text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(layout.fontName as CFString, layout.fontSize, nil),
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): makeParagraphStyle(layout: layout)
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGMutablePath()
        let textRect = CGRect(
            x: layout.contentInsets.left,
            y: layout.contentInsets.top,
            width: max(1, layout.viewportSize.width - layout.contentInsets.left - layout.contentInsets.right),
            height: max(1, layout.viewportSize.height - layout.contentInsets.top - layout.contentInsets.bottom)
        )
        path.addRect(textRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        let estimatedEndOffset = estimateByteOffset(
            visibleUTF16Length: visibleRange.length,
            window: window
        )

        return PageByteRange(
            bookID: bookID,
            pageIndex: 0,
            byteRange: window.startByteOffset..<estimatedEndOffset
        )
    }

    private func makeParagraphStyle(layout: ReadingLayout) -> CTParagraphStyle {
        var lineSpacing = layout.lineSpacing
        var paragraphSpacing = layout.paragraphSpacing
        return withUnsafePointer(to: &lineSpacing) { lineSpacingPointer in
            withUnsafePointer(to: &paragraphSpacing) { paragraphSpacingPointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(lineSpacingPointer)
                    ),
                    CTParagraphStyleSetting(
                        spec: .paragraphSpacing,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(paragraphSpacingPointer)
                    )
                ]
                return settings.withUnsafeBufferPointer { buffer in
                    CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
                }
            }
        }
    }

    private func estimateByteOffset(visibleUTF16Length: Int, window: TextWindow) -> UInt64 {
        guard visibleUTF16Length > 0 else {
            return window.startByteOffset
        }

        let visibleText = String(window.text.prefix(visibleUTF16Length))
        let visibleByteCount = UInt64(visibleText.utf8.count)
        return min(window.endByteOffset, window.startByteOffset + visibleByteCount)
    }
}
