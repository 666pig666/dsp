import SwiftUI
import Charts

struct SpectrumPage: View {
    let result: AnalysisResult
    @State private var showOctaveBands = false
    @State private var showThirdOctave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !result.spectrum.averageSpectrum.isEmpty {
                    spectrumChart
                        .frame(height: 250)
                }

                // Band toggles — custom capsule style
                HStack(spacing: 8) {
                    bandToggle("Octave Bands", $showOctaveBands)
                    bandToggle("1/3 Octave", $showThirdOctave)
                }

                if showOctaveBands {
                    bandChart(bands: result.spectrum.octaveBands)
                        .frame(height: 200)
                }

                if showThirdOctave {
                    bandChart(bands: result.spectrum.thirdOctaveBands)
                        .frame(height: 200)
                }

                spectralBalanceView
            }
            .padding()
        }
    }

    private func bandToggle(_ label: String, _ isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? Theme.bg0 : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn.wrappedValue ? Theme.accent : Theme.bg3)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
    }

    private var spectrumChart: some View {
        let maxPts = 500
        let avgStride = max(1, result.spectrum.averageSpectrum.count / maxPts)
        let avgData = stride(from: 0, to: result.spectrum.averageSpectrum.count, by: avgStride)
            .enumerated().map { (i, srcIdx) in
                SpectrumPoint(index: i,
                              frequency: Double(result.spectrum.frequencyAxis[srcIdx]),
                              level: Double(result.spectrum.averageSpectrum[srcIdx]),
                              series: "Average")
            }
        let peakStride = max(1, result.spectrum.peakHoldSpectrum.count / maxPts)
        let peakData = stride(from: 0, to: result.spectrum.peakHoldSpectrum.count, by: peakStride)
            .enumerated().map { (i, srcIdx) in
                SpectrumPoint(index: i + maxPts,
                              frequency: Double(result.spectrum.frequencyAxis[srcIdx]),
                              level: Double(result.spectrum.peakHoldSpectrum[srcIdx]),
                              series: "Peak")
            }

        return Chart {
            ForEach(avgData) { point in
                LineMark(
                    x: .value("Freq", point.frequency),
                    y: .value("dBFS", point.level)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(peakData) { point in
                LineMark(
                    x: .value("Freq", point.frequency),
                    y: .value("dBFS", point.level)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .lineStyle(StrokeStyle(lineWidth: 1.0))
            }
        }
        .chartForegroundStyleScale([
            "Average": Theme.chartSpecAvg,
            "Peak":    Theme.chartSpecPeak
        ])
        .chartXScale(type: .log)
        .chartYScale(domain: -100...0)
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

    private func bandChart(bands: [BandEnergy]) -> some View {
        Chart {
            ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                BarMark(
                    x: .value("Freq", formatFreq(band.centerFrequency)),
                    y: .value("dB", band.energyDB)
                )
                .foregroundStyle(Theme.chartSpecAvg)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.chartGrid)
                AxisValueLabel()
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.chartAxis)
            }
        }
    }

    private var spectralBalanceView: some View {
        let balance = result.spectrum.spectralBalance
        let bands: [(String, Double)] = [
            ("Sub", balance.subDB),
            ("Low", balance.lowDB),
            ("Low-Mid", balance.lowMidDB),
            ("High-Mid", balance.highMidDB),
            ("High", balance.highDB)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            Text("SPECTRAL BALANCE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)

            ForEach(bands, id: \.0) { name, db in
                HStack {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 70, alignment: .leading)

                    GeometryReader { geo in
                        let normalized = max(0, min(1, (db + 30) / 30))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * normalized, height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 16)

                    Text(String(format: "%.1f dB", db))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 60, alignment: .trailing)
                }
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

    private func formatFreq(_ freq: Double) -> String {
        freq >= 1000 ? String(format: "%.0fk", freq / 1000) : String(format: "%.0f", freq)
    }
}

// Index-based identity — stable across SwiftUI re-renders.
struct SpectrumPoint: Identifiable {
    let index: Int
    let frequency: Double
    let level: Double
    let series: String
    var id: Int { index }
}
