import SwiftUI

struct StereoPage: View {
    let result: AnalysisResult
    var comparisonStack: ComparisonStack? = nil

    private var isComparison: Bool {
        (comparisonStack?.files.count ?? 0) > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let stereo = result.stereo {
                    stereoContent(stereo)
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Stereo mode required")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Select Stereo channel mode to view stereo analysis.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    // MARK: - Stereo content

    @ViewBuilder
    private func stereoContent(_ stereo: StereoResult) -> some View {
        // Hero metrics
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("AVG CORRELATION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Text(String(format: "%.3f", stereo.averageCorrelation))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .tracking(-0.5)
                    .foregroundStyle(correlationColor(stereo.averageCorrelation))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: stereo.averageCorrelation)
            }
            VStack(spacing: 4) {
                Text("MIN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Text(String(format: "%.3f", stereo.minimumCorrelation))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(correlationColor(stereo.minimumCorrelation))
                Text("M/S RATIO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
                Text(msRatioText(stereo.midSideRatioDB))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)

        // Correlation time-series chart
        if !stereo.correlationTimeSeries.isEmpty {
            correlationChart
                .frame(height: 200)
        }

        // Stereograph
        if !stereo.stereographPoints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("GONIOMETER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                StereographView(points: stereo.stereographPoints)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
            }
        }
    }

    // MARK: - Correlation chart

    private var correlationChart: some View {
        var allSeries = [CanvasChartSeries]()
        var legendItems: [(String, Color)]? = nil

        if isComparison, let stack = comparisonStack {
            var items = [(String, Color)]()
            for (i, file) in stack.files.enumerated() {
                guard let stereo = file.stereo,
                      !stereo.correlationTimeSeries.isEmpty else { continue }
                let color   = Theme.fileColor(i)
                let hopSec  = stereo.blockDurationMs / 1000.0
                let count   = stereo.correlationTimeSeries.count
                let maxPts  = 600
                let step    = max(1, Double(count - 1) / Double(maxPts - 1))
                let vals = (0..<min(count, maxPts)).map { j -> Double in
                    let idx = min(Int(Double(j) * step), count - 1)
                    return stereo.correlationTimeSeries[idx]
                }
                let times = (0..<vals.count).map { j -> Double in
                    let idx = min(Int(Double(j) * step), count - 1)
                    return Double(idx) * hopSec
                }
                let name  = String(file.metadata.fileName.prefix(16))
                allSeries.append(CanvasChartSeries(
                    label: name, color: color, values: vals,
                    xValues: times,
                    lineWidth: i == 0 ? 1.5 : 1.0,
                    opacity: i == 0 ? 1.0 : 0.8
                ))
                items.append((name, color))
            }
            legendItems = items
        } else if let stereo = result.stereo {
            let series = stereo.correlationTimeSeries
            let hopSec = stereo.blockDurationMs / 1000.0
            let maxPts = 600
            let count  = series.count
            let step   = max(1.0, Double(count - 1) / Double(maxPts - 1))
            let vals  = (0..<min(count, maxPts)).map { j in
                series[min(Int(Double(j) * step), count - 1)]
            }
            let times = (0..<vals.count).map { j -> Double in
                let idx = min(Int(Double(j) * step), count - 1)
                return Double(idx) * hopSec
            }
            allSeries.append(CanvasChartSeries(
                label: "Correlation", color: Theme.chartShortTerm,
                values: vals, xValues: times, lineWidth: 1.5
            ))
        }

        return CanvasLineChart(
            series: allSeries,
            yDomain: -1...1,
            zeroLine: true,
            legendItems: legendItems
        )
    }

    // MARK: - Helpers

    private func correlationColor(_ value: Double) -> Color {
        if value < 0   { return Theme.error }
        if value < 0.5 { return Theme.warning }
        return Theme.pass
    }

    private func msRatioText(_ ratio: Double) -> String {
        if ratio.isInfinite { return "Mono" }
        return String(format: "%.1f dB", ratio)
    }
}

// Index-based identity — stable across SwiftUI re-renders.
struct CorrelationPoint: Identifiable {
    let index: Int
    let time: Double
    let value: Double
    var id: Int { index }
}
