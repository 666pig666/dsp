# SPECTRAL Advanced Visuals & Comparison Wiring — Claude Code Instructions

## CRITICAL CONSTRAINTS

- All chart rendering MUST use SwiftUI Canvas. Do NOT use SwiftUI Charts (LineMark, BarMark, etc.) — the previous SwiftUI Charts implementation caused SIGKILL memory crashes from O(N) view hierarchy allocation. Canvas renders everything in a single draw call.
- Do NOT store per-block FFT data for the entire file. Use fixed-size circular buffers (max 120 blocks) for waterfall and stereograph data.
- Do NOT add any external dependencies. Pure SwiftUI + Accelerate + AVFoundation.
- All new colors must come from Theme.swift. Do not hardcode hex values in views.

-----

## Part 1: Waterfall Spectrum Plot

### What It Is

A pseudo-3D visualization where successive FFT frames are stacked in depth, creating a “mountain range” effect that shows how the frequency spectrum evolves over time. Reference: iZotope Insight 2’s spectrogram / waterfall view.

### Data Storage

Add a new field to `SpectrumResult`:

```swift
struct SpectrumResult: Codable {
    // ... existing fields ...
    let waterfallFrames: [[Float]]  // Last 80 FFT magnitude frames, each downsampled to 256 bins
    let waterfallFrameCount: Int
}
```

In `SpectrumAnalyzer.swift`, during the FFT block loop:

- Maintain a circular buffer of the last 80 magnitude frames.
- Each frame is downsampled from the full FFT bin count to 256 bins (by taking the max magnitude within each group of bins). This caps memory at 80 × 256 × 4 bytes = ~80 KB regardless of file length.
- After the full-file pass, copy the circular buffer into `waterfallFrames` in chronological order (oldest first).

### Rendering (new view: `WaterfallView`)

Create `WaterfallView.swift` — a SwiftUI Canvas that draws the waterfall.

Drawing approach:

1. The canvas represents a virtual 3D space projected to 2D.
1. Draw frames back-to-front (painter’s algorithm). The oldest frame is at the back (top of canvas, smaller, more transparent). The newest frame is at the front (bottom of canvas, larger, fully opaque).
1. Each frame is a filled polygon: the frequency curve on top, a flat baseline on the bottom.
1. X-axis: frequency (0 to 256 bins, mapped logarithmically to canvas width).
1. Y-axis (vertical): amplitude in dB. Map -100 dBFS to baseline, 0 dBFS to max height.
1. Z-axis (depth): simulated by vertical offset and scale. Each successive frame is drawn slightly higher and slightly smaller than the one in front of it.

Perspective math per frame (where `i` is frame index, 0 = oldest/back, N-1 = newest/front):

```
let t = CGFloat(i) / CGFloat(frameCount - 1)  // 0 = back, 1 = front
let yOffset = (1.0 - t) * maxDepthOffset       // back frames shifted up
let scaleY = 0.3 + t * 0.7                     // back frames vertically compressed
let opacity = 0.15 + t * 0.85                  // back frames faded
```

Color: each frame’s fill uses a vertical gradient from the frame’s line color (top) to transparent (bottom). The line color itself is based on frame recency:

- Newest frames: Theme.accent (#4ECDC4)
- Oldest frames: Theme.accent at 15% opacity
- The fill below each curve: same color at 5-10% opacity, creating a translucent “mountain” effect.

For the frequency magnitude-to-color mapping (heat map style, optional enhancement):

- Map each bin’s dB value to a color gradient:
  - -100 dB: transparent
  - -60 dB: deep blue (#0A1628)
  - -40 dB: teal (#1A6B5A)
  - -20 dB: green (#2ECC71)
  - -10 dB: yellow (#E6A817)
  - 0 dB: red (#E74C6F)

### Integration

Add a toggle on the Spectrum page: “Waterfall” button. When active, replace the 2D average spectrum chart with the WaterfallView. The 2D chart and the waterfall are mutually exclusive — never render both simultaneously.

-----

## Part 2: Stereograph (Lissajous / Goniometer)

### What It Is

An X/Y plot where Left channel maps to one axis and Right channel maps to the other, rotated 45° so that mono content appears as a vertical line and stereo content spreads horizontally. Points are plotted with persistence decay and heat-mapped intensity. Reference: Blue Cat StereoScope Pro.

### Data Storage

Add a new field to `StereoResult`:

```swift
struct StereoResult: Codable {
    // ... existing fields ...
    let stereographPoints: [StereographPoint]  // Downsampled L/R pairs for display
}

struct StereographPoint: Codable {
    let m: Float  // mid = (L + R) / 2
    let s: Float  // side = (L - R) / 2
}
```

In `StereoAnalyzer.swift`:

- After computing correlation, sample the L/R data for the stereograph.
- Do NOT use every sample. For a 5-minute file at 48 kHz, that’s 14.4 million points — way too many.
- Sampling strategy: divide the file into 10,000 evenly-spaced points. At each point, take a short window (64 samples), compute the RMS of L and R over that window, then store the M/S pair. This gives 10,000 points that represent the average stereo position at each time slice.
- Additionally, store the peak L/R pair per window (not just RMS) to capture transient stereo excursions.
- Total: 10,000 StereographPoint entries = 80 KB. Acceptable.

### Rendering (new view: `StereographView`)

Create `StereographView.swift` — a SwiftUI Canvas.

Coordinate system:

- The display is a square canvas.
- X-axis: Side (S) component. Positive S = right-heavy, Negative S = left-heavy.
- Y-axis: Mid (M) component. Positive M = in-phase, Negative M = out-of-phase.
- The axes are rotated 45° from the standard L/R orientation, matching the standard goniometer convention.
- Draw axis lines: vertical center line (mono axis), horizontal center line (side axis), and diagonal lines at 45° marking L-only and R-only.

Drawing approach:

1. Background: solid Level 0 color.
1. Draw axis reference lines in Theme.gridColor, dashed.
1. Label the corners: “L” (top-left), “R” (top-right), “+M” (top-center), “-M” (bottom-center).
1. For each StereographPoint, plot a small dot at (S, M) mapped to canvas coordinates.
1. Intensity/color based on the magnitude of the point (sqrt(M² + S²)):
- Low magnitude (near silence): transparent / dark blue
- Medium: teal/green
- High: yellow/white
- Use the same heat gradient as the waterfall.
1. Dot size: 2pt with 1pt gaussian blur (use `shadow(radius: 1)` on the fill, or just draw a 3pt circle at low opacity to simulate glow).
1. To create the “persistence” / density effect: points that overlap the same screen pixel accumulate brightness. Since we’re drawing 10,000 semi-transparent dots, areas with many overlapping points naturally appear brighter. This is the correct behavior — it’s additive blending simulated via opacity stacking.

### Integration

Add the StereographView to the Stereo/Phase page (Page 4). Place it below the correlation time series chart. Give it a square aspect ratio (`aspectRatio(1, contentMode: .fit)`) and a fixed height of 280pt.

It should only render when stereo data is available. Show “Stereo mode required” placeholder otherwise (same as existing behavior).

-----

## Part 3: Comparison Feature Wiring

The comparison data model (ComparisonStack), UI components (ComparisonPillBar, ComparisonSummaryTable), and delta computation all exist but are partially unwired. The following must be implemented:

### 3A: Spectral Overlay in Comparison Mode

On the Spectrum page, when `comparisonStack.files.count > 1`:

1. Draw all files’ average spectra on the same CanvasLineChart, each in its assigned comparison color (Theme.fileColors).
1. Add a “Difference” toggle. When active, instead of overlaying raw spectra, show the difference curves: `spectrum_B[bin] - spectrum_A[bin]` in dB for each comparison file. The difference is drawn on a zero-centered Y-axis (±6 dB default range, auto-scale if needed). The reference line at 0 dB is drawn in Theme.gridColor.
1. File A’s spectrum is always drawn. Files B/C/D difference curves use their assigned colors.

Implementation:

- `SpectrumPage` must accept `comparisonStack` as input (pass from ResultsView).
- In comparison mode, iterate `comparisonStack.files` and draw each file’s `spectrum.averageSpectrum` as a separate Canvas series.
- For the difference mode, compute the difference array at render time (it’s only 256-500 floats, negligible cost).

### 3B: Loudness Overlay in Comparison Mode

On the Loudness page, when comparison mode is active:

1. Draw all files’ short-term loudness time series overlaid on the same chart, each in its comparison color.
1. File A is drawn at full opacity. Files B/C/D at 80% opacity.
1. Each file’s integrated LUFS is shown as a dashed horizontal reference line in its color.
1. Add a “Delta” toggle: shows only the difference (B-A, C-A, D-A) over time. Y-axis becomes relative (±6 LU centered on 0).

### 3C: Crest Factor Overlay in Comparison Mode

On the Dynamics page, when comparison mode is active:

- Overlay crest factor time series from all files.
- Same color assignment pattern.

### 3D: Correlation Overlay in Comparison Mode

On the Stereo page, when comparison mode is active:

- Overlay correlation time series from all files.

### 3E: Comparison Table on Summary Dashboard

When comparison mode is active, the Summary Dashboard (Page 0) should show:

- A table with one row per metric, columns for each file.
- Delta values for files B/C/D relative to A.
- Delta color coding must be metric-aware:
  - **LUFS delta**: positive (louder) = amber/warning, negative (quieter) = neutral
  - **True Peak delta**: positive (hotter) = red/error, negative (more headroom) = green/pass
  - **PLR delta**: positive (more headroom) = green/pass, negative (less) = amber
  - **Crest Factor delta**: positive (more dynamic) = green, negative (more compressed) = amber
  - **Correlation delta**: positive (more correlated) = neutral, negative (less correlated) = amber
  - **LRA delta**: neutral (no directional judgment)
  - **RMS delta**: positive (louder) = amber, negative = neutral

This replaces the current `ComparisonSummaryTable` which colors all positive deltas red.

### 3F: Passing ComparisonStack Through the View Hierarchy

Currently, `ResultsView` receives `comparisonStack` but does NOT pass it to any child page. Fix:

Every detail page must accept an optional `ComparisonStack`:

```swift
struct LoudnessPage: View {
    let result: AnalysisResult
    var comparisonStack: ComparisonStack?
    // ...
}
```

In `ResultsView`, pass `comparisonStack` to each page:

```swift
LoudnessPage(result: result, comparisonStack: comparisonStack)
    .tag(1)
SpectrumPage(result: result, comparisonStack: comparisonStack)
    .tag(3)
// etc.
```

Each page checks `if let stack = comparisonStack, stack.files.count > 1` to decide whether to render comparison overlays.

### 3G: Comparison Compliance Grid

On the Compliance page, when comparison mode is active:

- Show all files as columns in the pass/fail grid.
- Each file’s name at the top of its column, colored with its comparison color.
- Each metric row shows measured value + pass/fail per file.

-----

## Part 4: CanvasLineChart Upgrades for Comparison

The existing `CanvasLineChart` already supports multiple series. For comparison mode, extend it:

1. Add support for a `legendItems` parameter: an array of `(String, Color)` tuples. If provided, draw a legend in the top-right corner of the chart: small color dot + filename, stacked vertically. Font: SF Mono 9pt.
1. Add support for a `zeroLine` parameter (Bool). When true, draw a prominent horizontal line at Y=0 (for difference/delta modes).
1. Add support for gradient fill below each series line (optional per series). When enabled, fill the area between the line and the X-axis baseline with a vertical gradient from the series color at 15% opacity (top) to transparent (bottom). This creates the “filled area” look seen in iZotope Insight’s loudness history.

-----

## Part 5: Chart Background Enhancement

Update `CanvasLineChart` background rendering:

1. Replace flat background with a subtle radial gradient: center is slightly lighter (`#12121E`), edges are darker (`#08080C`). This creates a subtle “glow from center” effect that makes the chart feel like a backlit display.
1. Add a thin 1pt border around the chart area in `#1E1E2E` (barely visible, defines the plot boundary).

-----

## Implementation Order

1. **Theme.swift updates** — Add new colors for heat gradient, waterfall, stereograph axes.
1. **SpectrumAnalyzer.swift** — Add waterfall circular buffer, downsample to 256 bins, store last 80 frames.
1. **StereoAnalyzer.swift** — Add stereograph point sampling (10,000 points).
1. **WaterfallView.swift** — New file. Canvas rendering of the waterfall.
1. **StereographView.swift** — New file. Canvas rendering of the Lissajous/goniometer.
1. **SpectrumPage.swift** — Add waterfall toggle, integrate WaterfallView.
1. **StereoPage.swift** — Integrate StereographView below correlation chart.
1. **CanvasLineChart.swift** — Add legend, zeroLine, gradient fill, background gradient.
1. **ResultsView.swift** — Pass comparisonStack to all child pages.
1. **All detail pages** — Add `comparisonStack` parameter, render overlays when active.
1. **SummaryDashboardPage.swift** — Metric-aware delta coloring in comparison table.
1. **CompliancePage.swift** — Multi-file column grid.
1. **ComparisonView.swift** — Fix delta color logic to be metric-directional.

-----

## Memory Budget Check

New allocations:

- Waterfall: 80 frames × 256 bins × 4 bytes = 80 KB per file
- Stereograph: 10,000 points × 8 bytes = 80 KB per file
- Total new: ~160 KB per file, ~640 KB for 4-file comparison

This is negligible relative to the existing analysis data. No risk of SIGKILL.

-----

## What NOT To Do

- Do NOT use SwiftUI Charts for any new visualization. Canvas only.
- Do NOT store full per-block FFT data for the entire file. Only the last 80 frames in a circular buffer.
- Do NOT render the waterfall and the 2D spectrum simultaneously. They are mutually exclusive (toggle).
- Do NOT draw more than 10,000 stereograph points. Performance on Canvas degrades past ~15,000 draw calls per frame.
- Do NOT use Metal or SceneKit for the waterfall. Canvas with painter’s algorithm is sufficient for 80 stacked curves and avoids a massive complexity increase.
- Do NOT use `blendMode(.plusLighter)` or other compositing modes on Canvas — they don’t work reliably across all iOS versions. Simulate additive blending with low-opacity overlapping circles.
- Do NOT use spring animations on chart transitions. Use `.easeInOut` only.
