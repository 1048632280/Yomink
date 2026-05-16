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

            // 🌟 1. 替换基础底色为“复古香色” (暖黄/羊皮纸色)
            UIColor(red: 0.925, green: 0.886, blue: 0.812, alpha: 1).setFill()
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
        // 增加晕染带的数量，模拟老纸张受潮泛黄的不均匀感
        for _ in 0..<50 { 
            let x = random.nextCGFloat(in: bounds.minX...bounds.maxX)
            let width = random.nextCGFloat(in: 4.0...15.0)
            let alpha = random.nextCGFloat(in: 0.01...0.025)
            // 🌟 2. 晕染颜色改为深褐色，而不是灰色
            context.setFillColor(UIColor(red: 0.65, green: 0.55, blue: 0.40, alpha: alpha).cgColor)
            context.fill(CGRect(x: x, y: bounds.minY, width: width, height: bounds.height))
        }
    }

    private static func drawFineVerticalFibers(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        context.setLineCap(.round)
        for _ in 0..<300 {
            let x = random.nextCGFloat(in: bounds.minX...bounds.maxX)
            let y = random.nextCGFloat(in: -bounds.height * 0.12...bounds.height)
            let length = random.nextCGFloat(in: bounds.height * 0.10...bounds.height * 0.60)
            let lineWidth = random.nextCGFloat(in: 0.2...0.8)
            let alpha = random.nextCGFloat(in: 0.015...0.04)
            
            // 🌟 3. 纸浆纤维也改为枯草色/褐色
            let isDarkFiber = random.nextBool()
            let r: CGFloat = isDarkFiber ? 0.50 : 0.85
            let g: CGFloat = isDarkFiber ? 0.40 : 0.80
            let b: CGFloat = isDarkFiber ? 0.30 : 0.70

            context.setStrokeColor(UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor)
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: CGPoint(x: x, y: max(bounds.minY, y)))
            context.addLine(to: CGPoint(x: x + random.nextCGFloat(in: -0.5...0.5), y: min(bounds.maxY, y + length)))
            context.strokePath()
        }
    }

    private static func drawFaintHorizontalGrain(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        context.setLineWidth(0.3)
        var y = bounds.minY + 1
        while y < bounds.maxY {
            let alpha = random.nextCGFloat(in: 0.005...0.015)
            // 🌟 4. 横向纹理改为浅褐色
            context.setStrokeColor(UIColor(red: 0.6, green: 0.5, blue: 0.4, alpha: alpha).cgColor)
            context.beginPath()
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y + random.nextCGFloat(in: -0.1...0.1)))
            context.strokePath()
            y += random.nextCGFloat(in: 2.0...6.0)
        }
    }

    private static func drawPaperSpeckles(
        in context: CGContext,
        bounds: CGRect,
        random: inout SeededRandom
    ) {
        // 增加杂质斑点，让纸张看起来更有质感
        for _ in 0..<800 {
            let size = random.nextCGFloat(in: 0.2...0.8)
            let alpha = random.nextCGFloat(in: 0.01...0.035)
            // 🌟 5. 杂质设为深棕色
            context.setFillColor(UIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: alpha).cgColor)
            
            let rect = CGRect(
                x: random.nextCGFloat(in: bounds.minX...bounds.maxX),
                y: random.nextCGFloat(in: bounds.minY...bounds.maxY),
                width: size,
                height: size
            )
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
