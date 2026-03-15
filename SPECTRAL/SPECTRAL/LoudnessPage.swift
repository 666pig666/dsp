import SwiftUI
import Charts

struct LoudnessPage: View {
    let result: AnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Primary readout
                VStack(spacing: 4) {
                    Text("Integrated Loudness")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                    Text(String(format: "%.1f LUFS", result.loudness.integratedLUFS))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x00D4FF))
                }
                .frame(maxWidth: .infinity)

                // Secondary readouts
                HStack(spacing: 20) {
                    readout("Momentary Max", String(format: "%.1f LUFS", result.loudness.momentaryMaxLUFS))
                    readout("Short-term Max", String(format: "%.1f LUFS", result.loudness.shortTermMaxLUFS))
                    readout("LRA", String(format: "%.1f LU", result.loudness.loudnessRangeLU))
                }
                .frame(maxWidth: .infinity)

                // Loudness over time chart
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
                .font(.caption2)
                .foregroundStyle(Color(hex: 0x888888))
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Color(hex: 0xE0E0E0))
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
                .opacity(0.5)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(shortTermData) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("LUFS", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(y: .value("Integrated", result.loudness.integratedLUFS))
                .foregroundStyle(Color(hex: 0x00D4FF))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
        }
        .chartForegroundStyleScale([
            "Momentary": Color(hex: 0x888888),
            "Short-term": Color(hex: 0x00CC66)
        ])
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color(hex: 0x333333))
                AxisValueLabel().foregroundStyle(Color(hex: 0x888888))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color(hex: 0x333333))
                AxisValueLabel().foregroundStyle(Color(hex: 0x888888))
            }
        }
    }

    /// Downsample a time series to at most `maxPoints` by picking evenly-spaced indices.
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
// UUID() created a new identity every render, causing SwiftUI to tear down
// and rebuild every LineMark on each render pass, spiking memory during
// TabView page transitions on long files.
struct LoudnessPoint: Identifiable {
    let index: Int
    let time: Double
    let value: Double
    let series: String
    var id: Int { index }
}
