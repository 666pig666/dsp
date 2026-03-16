import SwiftUI

// MARK: - Data types

/// A single data series for CanvasLineChart.
struct CanvasChartSeries {
    let label: String
    let color: Color
    /// Y values in data space.
    let values: [Double]
    /// Optional X values in data space. If nil, uses 0..<values.count as X.
    var xValues: [Double]? = nil
    var lineWidth: CGFloat = 1.5
    var opacity: Double = 1.0
    /// Fill the area between the line and the bottom of the chart with a gradient.
    var gradientFill: Bool = false
    var dashed: Bool = false
}

/// A horizontal reference line at a fixed Y value.
struct CanvasReferenceLine {
    let y: Double
    let color: Color
    var dashed: Bool = true
}

// MARK: - CanvasLineChart

/// A SwiftUI Canvas-based line chart.
/// Supports multiple series, optional gradient fills, reference lines, a zero line, and a legend.
/// Uses a subtle radial-gradient background and a 1pt border per the design spec.
struct CanvasLineChart: View {
    let series: [CanvasChartSeries]
    let yDomain: ClosedRange<Double>

    /// X domain. If nil, auto-computed from xValues (or 0...count−1).
    var xDomain: ClosedRange<Double>? = nil
    /// Map X values logarithmically (for spectrum frequency axis).
    var logScaleX: Bool = false
    /// Draw a prominent horizontal line at Y = 0.
    var zeroLine: Bool = false
    /// Additional horizontal reference lines.
    var referenceLines: [CanvasReferenceLine] = []
    /// If provided, a legend is drawn in the top-right corner.
    var legendItems: [(String, Color)]? = nil

    var body: some View {
        Canvas { context, size in
            drawBackground(context: context, size: size)
            drawBorder(context: context, size: size)
            drawGrid(context: context, size: size)

            let mapX = makeXMapper(size: size)
            let mapY = makeYMapper(size: size)

            if zeroLine { drawZeroLine(context: context, size: size, mapY: mapY) }
            for ref in referenceLines { drawReferenceLine(context: context, size: size, ref: ref, mapY: mapY) }
            for s in series { drawSeries(context: context, size: size, s: s, mapX: mapX, mapY: mapY) }
            if let legend = legendItems, !legend.isEmpty {
                drawLegend(context: context, size: size, items: legend)
            }
        }
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        let bgGradient = Gradient(colors: [Theme.chartBgCenter, Theme.chartBgEdge])
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                bgGradient,
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.65
            )
        )
    }

    // MARK: - Border

    private func drawBorder(context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
        context.stroke(Path(rect), with: .color(Theme.chartBorder), lineWidth: 1)
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let steps = 5
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let y = t * size.height
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(p, with: .color(Theme.chartGrid), lineWidth: 0.5)
        }
    }

    // MARK: - Y mapper

    private func makeYMapper(size: CGSize) -> (Double) -> CGFloat {
        let yLow = yDomain.lowerBound
        let yHigh = yDomain.upperBound
        let range = yHigh - yLow
        return { val in
            let t = range != 0 ? (val - yLow) / range : 0.5
            return CGFloat(1.0 - t) * size.height
        }
    }

    // MARK: - X mapper

    private func makeXMapper(size: CGSize) -> (Int, [Double]?) -> CGFloat {
        // Compute effective X domain
        let xLow: Double
        let xHigh: Double
        if let dom = xDomain {
            xLow = dom.lowerBound
            xHigh = dom.upperBound
        } else if let firstSeries = series.first, let xVals = firstSeries.xValues, !xVals.isEmpty {
            xLow = xVals.first!
            xHigh = xVals.last!
        } else {
            xLow = 0
            let maxCount = series.map { $0.values.count }.max() ?? 1
            xHigh = Double(max(1, maxCount - 1))
        }

        if logScaleX {
            let logLow  = log10(max(xLow,  20.0))
            let logHigh = log10(max(xHigh, 20.0))
            let logRange = logHigh - logLow
            return { idx, xVals in
                let xVal = xVals != nil ? xVals![idx] : Double(idx)
                let logVal = log10(max(xVal, 20.0))
                let t = logRange != 0 ? (logVal - logLow) / logRange : 0
                return CGFloat(t) * size.width
            }
        } else {
            let xRange = xHigh - xLow
            return { idx, xVals in
                let xVal = xVals != nil ? xVals![idx] : Double(idx)
                let t = xRange != 0 ? (xVal - xLow) / xRange : 0
                return CGFloat(t) * size.width
            }
        }
    }

    // MARK: - Zero line

    private func drawZeroLine(context: GraphicsContext, size: CGSize, mapY: (Double) -> CGFloat) {
        let y = mapY(0)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(p, with: .color(Theme.chartAxis), lineWidth: 1)
    }

    // MARK: - Reference lines

    private func drawReferenceLine(context: GraphicsContext, size: CGSize, ref: CanvasReferenceLine, mapY: (Double) -> CGFloat) {
        let y = mapY(ref.y)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: size.width, y: y))
        if ref.dashed {
            context.stroke(p, with: .color(ref.color), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        } else {
            context.stroke(p, with: .color(ref.color), lineWidth: 1)
        }
    }

    // MARK: - Series

    private func drawSeries(
        context: GraphicsContext,
        size: CGSize,
        s: CanvasChartSeries,
        mapX: (Int, [Double]?) -> CGFloat,
        mapY: (Double) -> CGFloat
    ) {
        guard !s.values.isEmpty else { return }
        let count = s.values.count

        // Build line path
        var linePath = Path()
        for i in 0..<count {
            let x = mapX(i, s.xValues)
            let y = mapY(s.values[i])
            if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
            else       { linePath.addLine(to: CGPoint(x: x, y: y)) }
        }

        // Gradient fill below line
        if s.gradientFill {
            var fillPath = linePath
            let lastX = mapX(count - 1, s.xValues)
            let firstX = mapX(0, s.xValues)
            fillPath.addLine(to: CGPoint(x: lastX,  y: size.height))
            fillPath.addLine(to: CGPoint(x: firstX, y: size.height))
            fillPath.closeSubpath()
            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [s.color.opacity(0.15), s.color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint:   CGPoint(x: 0, y: size.height)
                )
            )
        }

        // Stroke
        let strokeStyle = s.dashed
            ? StrokeStyle(lineWidth: s.lineWidth, dash: [6, 4])
            : StrokeStyle(lineWidth: s.lineWidth)
        context.stroke(linePath, with: .color(s.color.opacity(s.opacity)), style: strokeStyle)
    }

    // MARK: - Legend

    private func drawLegend(context: GraphicsContext, size: CGSize, items: [(String, Color)]) {
        let rightEdge: CGFloat = size.width - 8
        let dotSize: CGFloat   = 7
        let rowHeight: CGFloat = 14
        var yOffset: CGFloat   = 8

        for item in items {
            // Color dot
            let dotX = rightEdge - 80
            context.fill(
                Path(ellipseIn: CGRect(x: dotX, y: yOffset, width: dotSize, height: dotSize)),
                with: .color(item.1)
            )
            // Label
            let label = Text(item.0)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
            context.draw(label, at: CGPoint(x: dotX + dotSize + 3, y: yOffset), anchor: .topLeading)
            yOffset += rowHeight
        }
    }
}
