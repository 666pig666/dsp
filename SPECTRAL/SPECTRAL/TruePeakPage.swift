import SwiftUI
import Charts

struct TruePeakPage: View {
    let result: AnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero readout
                VStack(spacing: 4) {
                    Text("MAX TRUE PEAK (\(result.truePeak.oversamplingRatio)x)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", result.truePeak.maxTruePeakDBTP))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .tracking(-0.5)
                            .foregroundStyle(truePeakColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: result.truePeak.maxTruePeakDBTP)
                        Text("dBTP")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                // Per-channel values
                HStack(spacing: 20) {
                    ForEach(Array(result.truePeak.perChannelTruePeakDBTP.enumerated()), id: \.offset) { idx, val in
                        let label = result.truePeak.perChannelTruePeakDBTP.count == 1 ? "Mono" : (idx == 0 ? "Left" : "Right")
                        VStack(spacing: 4) {
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                            Text(String(format: "%.1f dBTP", val))
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Peak location
                VStack(spacing: 4) {
                    Text("PEAK LOCATION")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    Text(String(format: "%.3f s", result.truePeak.peakTimeSeconds))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity)

                // Threshold references card
                VStack(alignment: .leading, spacing: 10) {
                    Text("THRESHOLD REFERENCES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    thresholdBar(label: "-1.0 dBTP (streaming)", threshold: -1.0)
                    thresholdBar(label: "-2.0 dBTP (broadcast)", threshold: -2.0)
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

    private var truePeakColor: Color {
        let tp = result.truePeak.maxTruePeakDBTP
        if tp > -1.0 { return Theme.error }
        if tp > -2.0 { return Theme.warning }
        return Theme.pass
    }

    private func thresholdBar(label: String, threshold: Double) -> some View {
        let peak = result.truePeak.maxTruePeakDBTP
        let passed = peak <= threshold
        let color: Color = passed ? Theme.pass : Theme.error

        return HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 4)
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(String(format: "%+.1f dB", peak - threshold))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
