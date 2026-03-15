import SwiftUI
import Charts

struct LoudnessPage: View {
    let result: AnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Primary readout — hero metric
                VStack(spacing: 4) {
                    Text("INTEGRATED LOUDNESS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", result.loudness.integratedLUFS))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: result.loudness.integratedLUFS)
                        Text("LUFS")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                // Secondary readouts
                HStack(spacing: 20) {
                    readout("Momentary Max", String(format: "%.1f LUFS", result.loudness.momentaryMaxLUFS))
                    readout("Short-term Max", String(format: "%.1f LUFS", result.loudness.shortTermMaxLUFS))
                    readout("LRA", String(format: "%.1f LU", result.loudness.loudnessRangeLU))
                }
                .frame(maxWidth: .infinity)

                if !result.loudness.momentaryTimeSeries.isEmpty {
                    loudnessChart
                        .frame(height: 250)
                }
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

    private var loudnessChart: some View {
        let hopMs = result.loudness.blockDurationMs
        let maxPoints = 600

        let momentaryData = downsample(result.loudness.momentaryTimeSeries, maxPoints: maxPoints)
            .enumerated().map { (i, pair) in
                LoudnessPoint(index: i, time: pair.time * hopMs / 1000.0,
                              value: max(pair.value, -70), series: "Momentary")
            }
        let shortTermData = downsample(result.loudness.shortTermTimeSeries, maxPoints: maxPoints)
            .enumerated().map { (i, pair) in
                LoudnessPoint(index: i + maxPoints, time: pair.time,
                              value: max(pair.value, -70), series: "Short-term")
            }

        return Chart {
            ForEach(momentaryData) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("LUFS", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .opacity(0.4)
                .lineStyle(StrokeStyle(lineWidth: 1.0))
            }
            ForEach(shortTermData) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("LUFS", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Integrated", result.loudness.integratedLUFS))
                .foregroundStyle(Theme.chartIntegrated)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .chartForegroundStyleScale([
            "Momentary":   Theme.chartMomentary,
            "Short-term":  Theme.chartShortTerm
        ])
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.chartGrid)
                AxisValueLabel()
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.chartAxis)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.chartGrid)
                AxisValueLabel()
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.chartAxis)
            }
        }
    }

    private func downsample(_ series: [Double], maxPoints: Int) -> [(time: Double, value: Double)] {
        guard series.count > maxPoints else {
            return series.enumerated().map { (time: Double($0.offset), value: $0.element) }
        }
        let step = Double(series.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { i in
            let idx = min(Int(Double(i) * step), series.count - 1)
            return (time: Double(idx), value: series[idx])
        }
    }
}

// Index-based identity — stable across SwiftUI re-renders.
struct LoudnessPoint: Identifiable {
    let index: Int
    let time: Double
    let value: Double
    let series: String
    var id: Int { index }
}
