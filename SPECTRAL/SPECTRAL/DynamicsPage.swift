import SwiftUI
import Charts

struct DynamicsPage: View {
    let result: AnalysisResult

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

    private var crestChart: some View {
        let series = result.dynamics.crestFactorTimeSeries
        let hopSec = result.dynamics.blockDurationMs / 1000.0
        let maxPoints = 600

        let data: [CrestPoint]
        if series.count <= maxPoints {
            data = series.enumerated().map { (i, val) in
                CrestPoint(index: i, time: Double(i) * hopSec, value: val)
            }
        } else {
            let step = Double(series.count - 1) / Double(maxPoints - 1)
            data = (0..<maxPoints).map { i in
                let idx = min(Int(Double(i) * step), series.count - 1)
                return CrestPoint(index: i, time: Double(idx) * hopSec, value: series[idx])
            }
        }

        return Chart {
            ForEach(data) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Crest", point.value)
                )
                .foregroundStyle(Theme.chartCrest)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("8 dB", 8))
                .foregroundStyle(Theme.chartThreshold)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
            RuleMark(y: .value("14 dB", 14))
                .foregroundStyle(Theme.pass)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
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
