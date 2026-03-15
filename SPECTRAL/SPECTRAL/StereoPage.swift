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

    @ViewBuilder
    private func stereoContent(_ stereo: StereoResult) -> some View {
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
                .foregroundStyle(Theme.chartShortTerm)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.chartAxis)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .chartYScale(domain: -1...1)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.chartGrid)
                AxisValueLabel()
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.chartAxis)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.chartGrid)
                AxisValueLabel()
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.chartAxis)
            }
        }
    }

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
