import SwiftUI
import Charts

struct StereoPage: View {
    let result: AnalysisResult

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
                            .foregroundStyle(Color(hex: 0x888888))
                        Text("Stereo mode required")
                            .font(.title3)
                            .foregroundStyle(Color(hex: 0x888888))
                        Text("Select Stereo channel mode to view stereo analysis.")
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0x888888))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func stereoContent(_ stereo: StereoResult) -> some View {
        // Readouts
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Avg Correlation")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x888888))
                Text(String(format: "%.3f", stereo.averageCorrelation))
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(correlationColor(stereo.averageCorrelation))
            }
            VStack(spacing: 4) {
                Text("Min Correlation")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x888888))
                Text(String(format: "%.3f", stereo.minimumCorrelation))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(correlationColor(stereo.minimumCorrelation))
            }
            VStack(spacing: 4) {
                Text("M/S Ratio")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x888888))
                Text(msRatioText(stereo.midSideRatioDB))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(Color(hex: 0xE0E0E0))
            }
        }
        .frame(maxWidth: .infinity)

        // Correlation over time
        if !stereo.correlationTimeSeries.isEmpty {
            correlationChart(stereo)
                .frame(height: 250)
        }
    }

    private func correlationChart(_ stereo: StereoResult) -> some View {
        let series = stereo.correlationTimeSeries
        let hopSec = stereo.blockDurationMs / 1000.0
        let maxPoints = 600

        let data: [CorrelationPoint]
        if series.count <= maxPoints {
            data = series.enumerated().map { (i, val) in
                CorrelationPoint(index: i, time: Double(i) * hopSec, value: val)
            }
        } else {
            let step = Double(series.count - 1) / Double(maxPoints - 1)
            data = (0..<maxPoints).map { i in
                let idx = min(Int(Double(i) * step), series.count - 1)
                return CorrelationPoint(index: i, time: Double(idx) * hopSec, value: series[idx])
            }
        }

        return Chart {
            ForEach(data) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Correlation", point.value)
                )
                .foregroundStyle(Color(hex: 0x00D4FF))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color(hex: 0x888888))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: -1...1)
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

    private func correlationColor(_ value: Double) -> Color {
        if value < 0   { return Color(hex: 0xFF3366) }
        if value < 0.5 { return Color(hex: 0xFFB800) }
        return Color(hex: 0x00CC66)
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
