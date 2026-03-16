import SwiftUI

/// Pseudo-3D waterfall spectrum view.
/// Draws successive FFT frames stacked in depth using the painter's algorithm
/// (oldest frame at back, newest at front). All rendering is done in a single
/// SwiftUI Canvas draw call.
struct WaterfallView: View {
    /// FFT magnitude frames in dBFS, each with 256 bins. Oldest first.
    let frames: [[Float]]

    /// Maximum depth offset in points — how far back the oldest frame is pushed.
    var maxDepthOffset: CGFloat = 80

    var body: some View {
        Canvas { context, size in
            guard frames.count > 1 else { return }

            drawBackground(context: context, size: size)
            drawFrames(context: context, size: size)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [Theme.chartBgCenter, Theme.chartBgEdge]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.65
            )
        )
        // Border
        context.stroke(
            Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)),
            with: .color(Theme.chartBorder),
            lineWidth: 1
        )
    }

    // MARK: - Frame rendering

    private func drawFrames(context: GraphicsContext, size: CGSize) {
        let frameCount = frames.count
        let binCount = frames[0].count

        // Drawing area: leave room at top for depth offset
        let plotHeight = size.height - maxDepthOffset
        let plotWidth  = size.width

        for i in 0..<frameCount {
            let t = CGFloat(i) / CGFloat(frameCount - 1)   // 0 = oldest/back, 1 = newest/front

            let yOffset  = (1.0 - t) * maxDepthOffset
            let scaleY   = 0.3 + t * 0.7
            let opacity  = 0.15 + t * 0.85

            let lineColor = Theme.accent.opacity(opacity)
            let fillColor = Theme.accent.opacity(opacity * 0.08)

            // Map bin index to log-scaled X
            let mapX: (Int) -> CGFloat = { bin in
                // Treat bin as a frequency from 1 to 256, map logarithmically
                let logMin = log10(1.0)
                let logMax = log10(Double(binCount))
                let logVal = log10(max(1.0, Double(bin + 1)))
                let t = (logVal - logMin) / (logMax - logMin)
                return CGFloat(t) * plotWidth
            }

            // Map dB magnitude to Y within this frame's scaled plot area
            // -100 dBFS → baseline, 0 dBFS → max height
            let frameBaseline = maxDepthOffset + plotHeight - yOffset
            let mapY: (Float) -> CGFloat = { db in
                let clamped = max(-100, min(0, Double(db)))
                let t = (clamped + 100.0) / 100.0
                return frameBaseline - CGFloat(t) * plotHeight * scaleY
            }

            let frame = frames[i]

            // Build polygon: curve on top, flat baseline on bottom
            var path = Path()
            for b in 0..<binCount {
                let x = mapX(b)
                let y = mapY(frame[b])
                if b == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else       { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            // Close polygon at the bottom
            path.addLine(to: CGPoint(x: mapX(binCount - 1), y: frameBaseline))
            path.addLine(to: CGPoint(x: mapX(0),            y: frameBaseline))
            path.closeSubpath()

            // Fill
            context.fill(path, with: .color(fillColor))

            // Re-draw just the top curve as a stroke
            var linePath = Path()
            for b in 0..<binCount {
                let x = mapX(b)
                let y = mapY(frame[b])
                if b == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
                else       { linePath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(linePath, with: .color(lineColor), lineWidth: 0.8)
        }
    }
}
