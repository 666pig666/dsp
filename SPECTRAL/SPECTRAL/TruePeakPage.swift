import SwiftUI
import Charts

struct TruePeakPage: View {
    let result: AnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Primary readout
                VStack(spacing: 4) {
                    Text("Max True Peak (\(result.truePeak.oversamplingRatio)x)")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                    Text(String(format: "%.1f dBTP", result.truePeak.maxTruePeakDBTP))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(truePeakColor)
                }
                .frame(maxWidth: .infinity)

                // Per-channel values
                HStack(spacing: 20) {
                    ForEach(Array(result.truePeak.perChannelTruePeakDBTP.enumerated()), id: \.offset) { idx, val in
                        let label = result.truePeak.perChannelTruePeakDBTP.count == 1 ? "Mono" : (idx == 0 ? "Left" : "Right")
                        VStack(spacing: 4) {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(Color(hex: 0x888888))
                            Text(String(format: "%.1f dBTP", val))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Color(hex: 0xE0E0E0))
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Peak location
                VStack(spacing: 4) {
                    Text("Peak Location")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                    Text(String(format: "%.3f s", result.truePeak.peakTimeSeconds))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color(hex: 0xE0E0E0))
                }
                .frame(maxWidth: .infinity)

                // Threshold references
                VStack(alignment: .leading, spacing: 8) {
                    Text("Threshold References")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                    thresholdBar(label: "-1.0 dBTP (streaming)", threshold: -1.0)
                    thresholdBar(label: "-2.0 dBTP (broadcast)", threshold: -2.0)
                }
                .padding()
                .background(Color(hex: 0x1A1A2E))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    private var truePeakColor: Color {
        let tp = result.truePeak.maxTruePeakDBTP
        if tp > -1.0 { return Color(hex: 0xFF3366) }
        if tp > -2.0 { return Color(hex: 0xFFB800) }
        return Color(hex: 0x00CC66)
    }

    private func thresholdBar(label: String, threshold: Double) -> some View {
        let peak = result.truePeak.maxTruePeakDBTP
        let passed = peak <= threshold

        return HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? Color(hex: 0x00CC66) : Color(hex: 0xFF3366))
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: 0xE0E0E0))
            Spacer()
            Text(String(format: "%+.1f dB", peak - threshold))
                .font(.caption.monospacedDigit())
                .foregroundStyle(passed ? Color(hex: 0x00CC66) : Color(hex: 0xFF3366))
        }
    }
}
