# SPECTRAL UI Overhaul — Sacred Geometry / Cymatics / Wireframe Aesthetic

## Design Vision

SPECTRAL should look like a piece of military-grade signal intelligence equipment designed by someone who studies Metatron's Cube. The visual language is: wireframe sacred geometry as structural UI elements, cymatics-inspired patterns that respond to the audio data, and a cold technical precision that feels like staring into a oscilloscope from the future.

References: TouchDesigner sacred geometry patches, Chladni plate patterns, wireframe brane visualizations, the aesthetic of Necro Deathmort album art meets a radar display.

NOT a generic dark app with rounded rectangles. Every surface should feel like it was etched with a laser on obsidian.

---

## CRITICAL CONSTRAINTS

- All decorative rendering MUST use SwiftUI Canvas. No SwiftUI Charts. No UIKit drawing.
- Decorative geometry is BACKGROUND ONLY. It must never obscure data readouts or chart traces.
- Keep decorative Canvas draw calls under 500 paths per view. Performance budget is real.
- All colors from Theme.swift. No hardcoded hex in views.
- No spring animations. Use `.easeInOut` or `.linear` only.
- Geometric patterns are STATIC or very slowly animated (>4 second cycles). No rapid movement — this is a precision instrument, not a screensaver.
- Do NOT add any external dependencies.

---

## Color Palette Update (Theme.swift)

Add these to the existing Theme:

```swift
// Sacred geometry wireframe colors
static let wireframe = Color(hex: 0x1A3A4A)        // Deep teal-blue, very subtle
static let wireframeActive = Color(hex: 0x2A5A6A)   // Slightly brighter for active elements
static let wireframeGlow = Color(hex: 0x4ECDC4)     // Accent teal with glow
static let wireframeDim = Color(hex: 0x0F2030)       // Nearly invisible structural lines

// Cymatics pattern colors
static let cymaticPrimary = Color(hex: 0x1A4A3A)    // Dark green-teal
static let cymaticSecondary = Color(hex: 0x0A2A2A)  // Near-black teal
static let cymaticNode = Color(hex: 0x3A8A7A)       // Brighter node points

// Data glow (for values that "emit light")
static let dataGlow = Color(hex: 0x4ECDC4)
static let dataGlowWarm = Color(hex: 0xE6A817)
static let dataGlowHot = Color(hex: 0xE74C6F)
```

---

## Part 1: Background Sacred Geometry Layer

### Concept
Every page has a faint sacred geometry pattern rendered behind the content. The pattern is specific to the page's domain — not random decoration, but thematically linked.

### Implementation: `GeometryBackgroundView`

Create `GeometryBackgroundView.swift`. This is a Canvas that renders behind page content via `.background()`.

It takes a `pattern` enum:

```swift
enum SacredPattern {
    case flowerOfLife      // Summary dashboard
    case standingWave      // Loudness page
    case radialNodes       // True Peak page
    case chladniPlate      // Spectrum page
    case lissajousCurve    // Stereo page
    case goldenSpiral      // Dynamics page
    case metatronsCube     // Compliance page
}
```

Each pattern is drawn in `Theme.wireframeDim` (nearly invisible) with key intersection points in `Theme.wireframe`. The entire pattern is at 15-25% opacity — it should be felt more than seen. When you look directly at it, you barely notice it. When you look at the data, the geometry frames your peripheral vision.

### Pattern Specifications

**Flower of Life (Summary Dashboard):**
- 7 overlapping circles arranged in the classic Flower of Life configuration.
- Center circle at canvas center. 6 surrounding circles with centers on the first circle's circumference, 60° apart.
- Line width: 0.5pt
- Color: `Theme.wireframeDim`
- Circle intersection points: 2pt dots in `Theme.wireframe`
- Scale to fill the canvas with ~40% padding on all sides.

```
Canvas math:
let r = min(size.width, size.height) * 0.3
let center = CGPoint(x: size.width / 2, y: size.height / 2)
// Center circle
path.addArc(center: center, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
// 6 surrounding circles
for i in 0..<6 {
    let angle = CGFloat(i) * .pi / 3
    let cx = center.x + r * cos(angle)
    let cy = center.y + r * sin(angle)
    path.addArc(center: CGPoint(x: cx, y: cy), radius: r, ...)
}
```

**Standing Wave (Loudness Page):**
- Horizontal sine waves at multiple harmonics, stacked vertically.
- 5 sine waves: fundamental + harmonics 2-5.
- Each wave is full canvas width.
- Amplitude decreases with harmonic number.
- Line width: 0.5pt, `Theme.wireframeDim`
- Node points (zero crossings) drawn as 2pt dots in `Theme.wireframe`

**Radial Nodes (True Peak Page):**
- Concentric circles radiating from center, like a radar display.
- 8 concentric circles, evenly spaced.
- 12 radial lines from center (every 30°).
- Line width: 0.5pt, `Theme.wireframeDim`
- Intersections: 1.5pt dots in `Theme.wireframe`

**Chladni Plate (Spectrum Page):**
- A Chladni pattern: the nodal lines of a vibrating square plate.
- Use the formula: `cos(n*pi*x/L) * cos(m*pi*y/L) - cos(m*pi*x/L) * cos(n*pi*y/L) = 0`
- Choose (n,m) = (3,2) for a visually interesting pattern.
- Render by sampling a grid of points and drawing contour lines where the function crosses zero.
- Simplified approach: sample a 100x100 grid. For each cell, if the sign of the function changes between adjacent samples, draw a short line segment.
- Color: `Theme.wireframeDim`. Line width: 0.5pt.

**Lissajous Curve (Stereo Page):**
- A static Lissajous figure: `x = sin(3t + pi/4)`, `y = sin(4t)` for `t` from 0 to 2π.
- This creates a complex interlocking pattern appropriate for the stereo analysis page.
- Line width: 0.5pt, `Theme.wireframeDim`
- Centered in the background, scaled to ~60% of canvas size.

**Golden Spiral (Dynamics Page):**
- A Fibonacci/golden spiral expanding from center.
- Draw as a series of quarter-circle arcs with increasing radii following the golden ratio (φ = 1.618).
- 8-10 quarter turns.
- Line width: 0.5pt, `Theme.wireframeDim`
- Add faint golden ratio rectangles behind the spiral.

**Metatron's Cube (Compliance Page):**
- 13 circles arranged in the Metatron's Cube configuration.
- 1 center + 6 inner ring + 6 outer ring.
- All 78 lines connecting each circle center to every other center.
- Line width: 0.3pt (thinner because there are many lines), `Theme.wireframeDim`
- Circle centers: 2pt dots in `Theme.wireframe`

### Usage

On every page view, wrap content:

```swift
ZStack {
    GeometryBackgroundView(pattern: .flowerOfLife)
        .opacity(0.2)
        .ignoresSafeArea()
    
    // Actual page content
    ScrollView { ... }
}
```

---

## Part 2: Metric Card Redesign — Hexagonal Wireframe

### Concept
Replace rounded rectangles with hexagonal card frames. Each metric card is contained in a hexagonal wireframe border instead of a rounded rect.

### Implementation

Create `HexCardView.swift`:

```swift
struct HexCardView<Content: View>: View {
    let status: MetricStatus
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .padding(16)
            .background(
                Canvas { ctx, size in
                    // Draw hexagonal border
                    let hex = hexagonPath(in: size)
                    ctx.stroke(hex, with: .color(borderColor), lineWidth: 1)
                    // Fill with very subtle dark
                    ctx.fill(hex, with: .color(Theme.level2.opacity(0.6)))
                    // Corner nodes: small dots at each vertex
                    for point in hexagonVertices(in: size) {
                        let dot = Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
                        ctx.fill(dot, with: .color(borderColor))
                    }
                }
            )
    }
    
    var borderColor: Color {
        switch status {
        case .pass: return Theme.pass.opacity(0.5)
        case .warning: return Theme.warning.opacity(0.5)
        case .error: return Theme.error.opacity(0.5)
        case .neutral: return Theme.wireframe
        }
    }
}
```

Hexagon math (flat-top orientation):
```
func hexagonPath(in size: CGSize) -> Path {
    let w = size.width
    let h = size.height
    let inset: CGFloat = 2
    var path = Path()
    // Flat-top hexagon vertices
    let cx = w / 2, cy = h / 2
    let rx = w / 2 - inset
    let ry = h / 2 - inset
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3 - .pi / 6  // Start at top-right
        let x = cx + rx * cos(angle)
        let y = cy + ry * sin(angle)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}
```

Replace all `MetricCard` usage on the Summary Dashboard with `HexCardView`. The grid should use a honeycomb-inspired layout where cards in odd rows are offset horizontally by half a card width (standard hex grid packing). This may require a custom layout instead of LazyVGrid.

If honeycomb layout is too complex, a standard 2-column grid with hexagonal card borders is acceptable as v1.

---

## Part 3: Hero Metric Glow Effect

### Concept
The primary metric value on each page (e.g., "-14.2 LUFS") should appear to emit light. Not a cheesy drop shadow — a controlled radial glow that makes the number look like it's being displayed on a high-end LED panel.

### Implementation

Create a `GlowText` view modifier:

```swift
struct GlowText: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.2), radius: radius * 2, x: 0, y: 0)
            .shadow(color: color.opacity(0.1), radius: radius * 3, x: 0, y: 0)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 4) -> some View {
        modifier(GlowText(color: color, radius: radius))
    }
}
```

Usage on hero metrics:
```swift
Text(String(format: "%.1f", result.loudness.integratedLUFS))
    .font(.system(size: 44, weight: .bold, design: .monospaced))
    .foregroundStyle(Theme.accent)
    .glow(Theme.dataGlow, radius: 6)
```

Apply `.