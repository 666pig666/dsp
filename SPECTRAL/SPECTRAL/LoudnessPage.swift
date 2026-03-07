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
        let momentaryData = result.loudness.momentaryTimeSeries.enumerated().map { (i, val) in
            LoudnessPoint(time: Double(i) * hopMs / 1000.0, value: max(val, -70), series: "Momentary")
        }
        let shortTermData = result.loudness.shortTermTimeSeries.enumerated().map { (i, val) in
            LoudnessPoint(time: Double(i) * 1.0, value: max(val, -70), series: "Short-term")
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
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color(hex: 0x333333))
                AxisValueLabel()
                    .foregroundStyle(Color(hex: 0x888888))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color(hex: 0x333333))
                AxisValueLabel()
                    .foregroundStyle(Color(hex: 0x888888))
            }
        }
    }
}

struct LoudnessPoint: Identifiable {
    let id = UUID()
    let time: Double
    let value: Double
    let series: String
}
