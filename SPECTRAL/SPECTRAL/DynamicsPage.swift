import SwiftUI

struct DynamicsPage: View {
    let result: AnalysisResult
    var comparisonStack: ComparisonStack? = nil

    private var isComparison: Bool {
        (comparisonStack?.files.count ?? 0) > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // PLR hero readout
                VStack(spacing: 4) {
                    Text("PEAK-TO-LOUDNESS RATIO")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", result.dynamics.plrDB))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: result.dynamics.plrDB)
                        Text("dB")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(plrInterpretation)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)

                // Crest factor readouts
                HStack(spacing: 20) {
                    readout("Avg Crest", String(format: "%.1f dB", result.dynamics.averageCrestFactor))
                    readout("Min Crest", String(format: "%.1f dB", result.dynamics.minimumCrestFactor))
                }
                .frame(maxWidth: .infinity)

                if !result.dynamics.crestFactorTimeSeries.isEmpty {
                    crestChart
                        .frame(height: 200)
                }

                // RMS readouts card
                VStack(alignment: .leading, spacing: 8) {
                    Text("RMS LEVELS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)

                    ForEach(Array(result.dynamics.rmsPerChannelDBFS.enumerated()), id: \.offset) { idx, rms in
                        let label = result.dynamics.rmsPerChannelDBFS.count == 1 ? "Mono" : (idx == 0 ? "Left" : "Right")
                        HStack {
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f dBFS", rms))
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    HStack {
                        Text("Summed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f dBFS", result.dynamics.rmsSummedDBFS))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(16)
                .background(Theme.bg2)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.bg4).frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .padding()
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Crest chart

    private var crestChart: some View {
        var allSeries  = [CanvasChartSeries]()
        var legendItems: [(String, Color)]? = nil

        if isComparison, let stack = comparisonStack {
            var items = [(String, Color)]()
            for (i, file) in stack.files.enumerated() {
                let series = file.dynamics.crestFactorTimeSeries
                guard !series.isEmpty else { continue }
                let color  = Theme.fileColor(i)
                let name   = String(file.metadata.fileName.prefix(16))
                let hopSec = file.dynamics.blockDurationMs / 1000.0
                let maxPts = 600
                let count  = series.count
                let step   = max(1.0, Double(count - 1) / Double(maxPts - 1))
                let maxIdx = min(count, maxPts)
                let vals  = (0..<maxIdx).map { j in series[min(Int(Double(j) * step), count - 1)] }
                let times = (0..<maxIdx).map { j -> Double in
                    Double(min(Int(Double(j) * step), count - 1)) * hopSec
                }
                allSeries.append(CanvasChartSeries(
                    label: name, color: color, values: vals, xValues: times,
                    lineWidth: i == 0 ? 1.5 : 1.0,
                    opacity:   i == 0 ? 1.0 : 0.8
                ))
                items.append((name, color))
            }
            legendItems = items
        } else {
            let series = result.dynamics.crestFactorTimeSeries
            let hopSec = result.dynamics.blockDurationMs / 1000.0
            let maxPts = 600
            let count  = series.count
            let step   = max(1.0, Double(count - 1) / Double(maxPts - 1))
            let maxIdx = min(count, maxPts)
            let vals  = (0..<maxIdx).map { j in series[min(Int(Double(j) * step), count - 1)] }
            let times = (0..<maxIdx).map { j -> Double in
                Double(min(Int(Double(j) * step), count - 1)) * hopSec
            }
            allSeries.append(CanvasChartSeries(
                label: "Crest", color: Theme.chartCrest,
                values: vals, xValues: times, lineWidth: 1.5
            ))
        }

        let yHigh = max(20.0, allSeries.flatMap(\.values).max().map { $0 + 3 } ?? 20)

        return CanvasLineChart(
            series: allSeries,
            yDomain: 0...yHigh,
            referenceLines: [
                CanvasReferenceLine(y: 8,  color: Theme.chartThreshold, dashed: true),
                CanvasReferenceLine(y: 14, color: Theme.pass,           dashed: true)
            ],
            legendItems: legendItems
        )
    }

    private var plrInterpretation: String {
        let plr = result.dynamics.plrDB
        if plr >= 12 { return "Well-preserved headroom" }
        if plr >= 8  { return "Moderate dynamic range" }
        if plr >= 6  { return "Limited dynamic range" }
        return "Aggressive limiting"
    }
}

// Index-based identity — stable across SwiftUI re-renders.
struct CrestPoint: Identifiable {
    let index: Int
    let time: Double
    let value: Double
    var id: Int { index }
}
