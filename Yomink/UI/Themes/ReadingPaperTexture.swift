import UIKit

@MainActor
enum ReadingPaperTexture {
    private static var cachedColors: [Int: UIColor] = [:]

    static func backgroundColor(scale: CGFloat = UIScreen.main.scale) -> UIColor {
        let normalizedScale = max(1, scale)
        let cacheKey = Int((normalizedScale * 100).rounded())
        if let color = cachedColors[cacheKey] {
            return color
        }

        let image = makeTileImage(scale: normalizedScale)
        let color = UIColor(patternImage: image)
        cachedColors[cacheKey] = color
        return color
    }

    private static func makeTileImage(scale: CGFloat) -> UIImage {
        let size = CGSize(width: 160, height: 320)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let bounds = CGRect(origin: .zero, size: size)

            UIColor(red: 0.968, green: 0.967, blue: 0.952, alpha: 1).setFill()
            context.fill(bounds)

            var random = SeededRandom(seed: 0x9F42_BA17)
            drawSoftVerticalBands(in: context, bounds: bounds, random: &random)
            drawFineVerticalFibers(in: context, bounds: bounds, random: &random)
            drawFaintHorizontalGrain(in: context, bounds: bounds, random: &random)
            drawPaperSpeckles(in: context, bounds: bounds, random: &random)
        }
    }

    private static func drawSoftVerticalBands(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        for _ in 0..<34 {
            let x = random.nextCGFloat(in: bounds.minX...bounds.maxX)
            let width = random.nextCGFloat(in: 2.5...11)
            let alpha = random.nextCGFloat(in: 0.006...0.018)
            let white = random.nextBool() ? CGFloat(1) : CGFloat(0.74)
            context.setFillColor(UIColor(white: white, alpha: alpha).cgColor)
            context.fill(CGRect(x: x, y: bounds.minY, width: width, height: bounds.height))
        }
    }

    private static func drawFineVerticalFibers(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        context.setLineCap(.round)
        for _ in 0..<260 {
            let x = random.nextCGFloat(in: bounds.minX...bounds.maxX)
            let y = random.nextCGFloat(in: -bounds.height * 0.12...bounds.height)
            let length = random.nextCGFloat(in: bounds.height * 0.18...bounds.height * 0.92)
            let lineWidth = random.nextCGFloat(in: 0.18...0.72)
            let alpha = random.nextCGFloat(in: 0.010...0.032)
            let white = random.nextBool() ? CGFloat(0.62) : CGFloat(1)

            context.setStrokeColor(UIColor(white: white, alpha: alpha).cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: CGPoint(x: x, y: max(bounds.minY, y)))
            context.addLine(to: CGPoint(x: x + random.nextCGFloat(in: -0.28...0.28), y: min(bounds.maxY, y + length)))
            context.strokePath()
        }
    }

    private static func drawFaintHorizontalGrain(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        context.setLineWidth(0.25)
        var y = bounds.minY + 1
        while y < bounds.maxY {
            let alpha = random.nextCGFloat(in: 0.004...0.011)
            context.setStrokeColor(UIColor(white: 0.70, alpha: alpha).cgColor)
            context.beginPath()
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y + random.nextCGFloat(in: -0.08...0.08)))
            context.strokePath()
            y += random.nextCGFloat(in: 3.5...7.5)
        }
    }

    private static func drawPaperSpeckles(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        for _ in 0..<620 {
            let size = random.nextCGFloat(in: 0.18...0.65)
            let alpha = random.nextCGFloat(in: 0.006...0.020)
            let white = random.nextBool() ? CGFloat(0.60) : CGFloat(1)
            let rect = CGRect(
                x: random.nextCGFloat(in: bounds.minX...bounds.maxX),
                y: random.nextCGFloat(in: bounds.minY...bounds.maxY),
                width: size,
                height: size
            )
            context.setFillColor(UIColor(white: white, alpha: alpha).cgColor)
            context.fill(rect)
        }
    }
}

private struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        let value = CGFloat(nextUnit())
        return range.lowerBound + (range.upperBound - range.lowerBound) * value
    }

    mutating func nextBool() -> Bool {
        nextUInt32() & 1 == 0
    }

    private mutating func nextUnit() -> Double {
        Double(nextUInt32()) / Double(UInt32.max)
    }

    private mutating func nextUInt32() -> UInt32 {
        state = 1664525 &* state &+ 1013904223
        return state
    }
}
