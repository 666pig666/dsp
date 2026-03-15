import SwiftUI
import Charts

struct SpectrumPage: View {
    let result: AnalysisResult
    @State private var showOctaveBands = false
    @State private var showThirdOctave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Spectrum chart
                if !result.spectrum.averageSpectrum.isEmpty {
                    spectrumChart
                        .frame(height: 250)
                }

                // Toggle for octave bands
                HStack {
                    Toggle("Octave Bands", isOn: $showOctaveBands)
                    Toggle("1/3 Octave", isOn: $showThirdOctave)
                }
                .font(.caption)
                .foregroundStyle(Color(hex: 0xE0E0E0))
                .tint(Color(hex: 0x00D4FF))

                if showOctaveBands {
                    bandChart(bands: result.spectrum.octaveBands, title: "Octave Bands")
                        .frame(height: 200)
                }

                if showThirdOctave {
                    bandChart(bands: result.spectrum.thirdOctaveBands, title: "1/3 Octave Bands")
                        .frame(height: 200)
                }

                // Spectral balance
                spectralBalanceView
            }
            .padding()
        }
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
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(peakData) { point in
                LineMark(
                    x: .value("Freq", point.frequency),
                    y: .value("dBFS", point.level)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartForegroundStyleScale([
            "Average": Color(hex: 0x00D4FF),
            "Peak": Color(hex: 0xFF3366)
        ])
        .chartXScale(type: .log)
        .chartYScale(domain: -100...0)
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

    private func bandChart(bands: [BandEnergy], title: String) -> some View {
        Chart {
            ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                BarMark(
                    x: .value("Freq", formatFreq(band.centerFrequency)),
                    y: .value("dB", band.energyDB)
                )
                .foregroundStyle(Color(hex: 0x00D4FF))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color(hex: 0x333333))
                AxisValueLabel().foregroundStyle(Color(hex: 0x888888))
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
            Text("Spectral Balance")
                .font(.headline)
                .foregroundStyle(Color(hex: 0xE0E0E0))

            ForEach(bands, id: \.0) { name, db in
                HStack {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                        .frame(width: 70, alignment: .leading)

                    GeometryReader { geo in
                        let normalized = max(0, min(1, (db + 30) / 30))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: 0x00D4FF))
                            .frame(width: geo.size.width * normalized)
                    }
                    .frame(height: 16)

                    Text(String(format: "%.1f dB", db))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(hex: 0xE0E0E0))
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color(hex: 0x1A1A2E))
        .cornerRadius(12)
    }

    private func formatFreq(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.0fk", freq / 1000)
        }
        return String(format: "%.0f", freq)
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
