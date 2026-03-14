import SwiftUI
import Charts

struct DynamicsPage: View {
    let result: AnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // PLR readout
                VStack(spacing: 4) {
                    Text("Peak-to-Loudness Ratio")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                    Text(String(format: "%.1f dB", result.dynamics.plrDB))
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x00D4FF))
                    Text(plrInterpretation)
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                }
                .frame(maxWidth: .infinity)

                // Crest factor readouts
                HStack(spacing: 20) {
                    readout("Avg Crest", String(format: "%.1f dB", result.dynamics.averageCrestFactor))
                    readout("Min Crest", String(format: "%.1f dB", result.dynamics.minimumCrestFactor))
                }
                .frame(maxWidth: .infinity)

                // Crest factor chart
                if !result.dynamics.crestFactorTimeSeries.isEmpty {
                    crestChart
                        .frame(height: 200)
                }

                // RMS readouts
                VStack(alignment: .leading, spacing: 8) {
                    Text("RMS Levels")
                        .font(.headline)
                        .foregroundStyle(Color(hex: 0xE0E0E0))

                    ForEach(Array(result.dynamics.rmsPerChannelDBFS.enumerated()), id: \.offset) { idx, rms in
                        let label = result.dynamics.rmsPerChannelDBFS.count == 1 ? "Mono" : (idx == 0 ? "Left" : "Right")
                        HStack {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(Color(hex: 0x888888))
                            Spacer()
                            Text(String(format: "%.1f dBFS", rms))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color(hex: 0xE0E0E0))
                        }
                    }
                    HStack {
                        Text("Summed")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: 0x888888))
                        Spacer()
                        Text(String(format: "%.1f dBFS", result.dynamics.rmsSummedDBFS))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(Color(hex: 0x00D4FF))
                    }
                }
                .padding()
                .background(Color(hex: 0x1A1A2E))
                .cornerRadius(12)
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
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(Color(hex: 0xE0E0E0))
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
                .foregroundStyle(Color(hex: 0x00D4FF))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("8 dB", 8))
                .foregroundStyle(Color(hex: 0xFFB800))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            RuleMark(y: .value("14 dB", 14))
                .foregroundStyle(Color(hex: 0x00CC66))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
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
