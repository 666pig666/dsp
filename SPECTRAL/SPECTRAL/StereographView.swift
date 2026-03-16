import SwiftUI

/// Lissajous / goniometer display.
/// Plots M/S stereo-position points as a heat-mapped scatter in a square Canvas.
/// Axes: X = Side (left/right balance), Y = Mid (mono energy).
/// Relies on overlapping semi-transparent dots for the density / persistence effect.
struct StereographView: View {
    let points: [StereographPoint]

    var body: some View {
        Canvas { context, size in
            guard !points.isEmpty else { return }

            drawBackground(context: context, size: size)
            drawAxes(context: context, size: size)
            drawLabels(context: context, size: size)
            drawPoints(context: context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Theme.bg0)
        )
        // Border
        context.stroke(
            Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)),
            with: .color(Theme.chartBorder),
            lineWidth: 1
        )
    }

    // MARK: - Axes

    private func drawAxes(context: GraphicsContext, size: CGSize) {
        let cx = size.width * 0.5
        let cy = size.height * 0.5

        let axisStyle = StrokeStyle(lineWidth: 1, dash: [4, 4])
        let color = Theme.stereographAxisColor

        // Vertical (mono axis)
        var v = Path()
        v.move(to: CGPoint(x: cx, y: 0))
        v.addLine(to: CGPoint(x: cx, y: size.height))
        context.stroke(v, with: .color(color), style: axisStyle)

        // Horizontal (side axis)
        var h = Path()
        h.move(to: CGPoint(x: 0, y: cy))
        h.addLine(to: CGPoint(x: size.width, y: cy))
        context.stroke(h, with: .color(color), style: axisStyle)

        // Diagonal L-only (top-left to bottom-right)
        var d1 = Path()
        d1.move(to: CGPoint(x: 0, y: 0))
        d1.addLine(to: CGPoint(x: size.width, y: size.height))
        context.stroke(d1, with: .color(color.opacity(0.5)), style: axisStyle)

        // Diagonal R-only (top-right to bottom-left)
        var d2 = Path()
        d2.move(to: CGPoint(x: size.width, y: 0))
        d2.addLine(to: CGPoint(x: 0, y: size.height))
        context.stroke(d2, with: .color(color.opacity(0.5)), style: axisStyle)
    }

    // MARK: - Corner labels

    private func drawLabels(context: GraphicsContext, size: CGSize) {
        let labelFont = Font.system(size: 9, weight: .medium, design: .monospaced)
        let labelColor = Theme.textTertiary
        let pad: CGFloat = 6

        let labels: [(String, CGPoint, UnitPoint)] = [
            ("L",  CGPoint(x: pad,                   y: pad),                    .topLeading),
            ("R",  CGPoint(x: size.width - pad,       y: pad),                    .topTrailing),
            ("+M", CGPoint(x: size.width * 0.5,       y: pad),                    .top),
            ("-M", CGPoint(x: size.width * 0.5,       y: size.height - pad),      .bottom)
        ]
        for (text, pt, anchor) in labels {
            context.draw(
                Text(text).font(labelFont).foregroundColor(labelColor),
                at: pt,
                anchor: anchor
            )
        }
    }

    // MARK: - Points

    private func drawPoints(context: GraphicsContext, size: CGSize) {
        // Find normalization scale
        var maxMag: Float = 0
        for p in points {
            let mag = sqrtf(p.m * p.m + p.s * p.s)
            if mag > maxMag { maxMag = mag }
        }
        guard maxMag > 0 else { return }

        let cx = size.width  * 0.5
        let cy = size.height * 0.5
        let scale = Double(min(size.width, size.height)) * 0.45 / Double(maxMag)

        let dotRadius: CGFloat = 1.5

        for pt in points {
            let m = Double(pt.m)
            let s = Double(pt.s)

            // M is always positive (RMS), placed upward from center
            // S can be negative (right-heavy) or positive (left-heavy)
            let px = cx + CGFloat(s * scale)
            let py = cy - CGFloat(m * scale)

            // Heat color by magnitude
            let mag = sqrt(m * m + s * s)
            let normalizedMag = mag / Double(maxMag)
            let dotColor = heatColor(normalizedMag)

            let dotRect = CGRect(
                x: px - dotRadius,
                y: py - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
        }
    }

    // MARK: - Heat color

    /// Maps 0…1 normalized magnitude to a heat-gradient color.
    private func heatColor(_ t: Double) -> Color {
        // Breakpoints: 0 → transparent, 0.2 → deepBlue, 0.4 → teal, 0.7 → green, 0.85 → yellow, 1 → red
        struct Stop { let t: Double; let color: Color }
        let stops: [Stop] = [
            Stop(t: 0.00, color: .clear),
            Stop(t: 0.20, color: Theme.heatDeepBlue),
            Stop(t: 0.40, color: Theme.heatTeal),
            Stop(t: 0.70, color: Theme.heatGreen),
            Stop(t: 0.85, color: Theme.heatYellow),
            Stop(t: 1.00, color: Theme.heatRed)
        ]

        for i in 1..<stops.count {
            let prev = stops[i - 1]
            let next = stops[i]
            if t <= next.t {
                let localT = next.t > prev.t ? (t - prev.t) / (next.t - prev.t) : 0
                return lerp(prev.color, next.color, localT)
            }
        }
        return Theme.heatRed
    }

    private func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        // Resolve to UIColor for component interpolation
        let uiA = UIColor(a)
        let uiB = UIColor(b)
        var rA: CGFloat = 0, gA: CGFloat = 0, bA: CGFloat = 0, aA: CGFloat = 0
        var rB: CGFloat = 0, gB: CGFloat = 0, bBVal: CGFloat = 0, aB: CGFloat = 0
        uiA.getRed(&rA, green: &gA, blue: &bA, alpha: &aA)
        uiB.getRed(&rB, green: &gB, blue: &bBVal, alpha: &aB)
        let ct = CGFloat(t)
        return Color(
            red:     Double(rA + (rB   - rA)    * ct),
            green:   Double(gA + (gB   - gA)    * ct),
            blue:    Double(bA + (bBVal - bA)   * ct),
            opacity: Double(aA + (aB   - aA)    * ct)
        )
    }
}
