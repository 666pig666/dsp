import SwiftUI

struct SummaryDashboardPage: View {
    let result: AnalysisResult
    @Binding var navigateTo: Int

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metadata section
                metadataSection

                // Metric cards
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(
                        title: "Integrated",
                        value: String(format: "%.1f", result.loudness.integratedLUFS),
                        unit: "LUFS",
                        status: loudnessStatus,
                        targetPage: 1,
                        navigateTo: $navigateTo
                    )

                    MetricCard(
                        title: "True Peak",
                        value: String(format: "%.1f", result.truePeak.maxTruePeakDBTP),
                        unit: "dBTP",
                        status: truePeakStatus,
                        targetPage: 2,
                        navigateTo: $navigateTo
                    )

                    MetricCard(
                        title: "LRA",
                        value: String(format: "%.1f", result.loudness.loudnessRangeLU),
                        unit: "LU",
                        status: .neutral,
                        targetPage: 1,
                        navigateTo: $navigateTo
                    )

                    MetricCard(
                        title: "PLR",
                        value: String(format: "%.1f", result.dynamics.plrDB),
                        unit: "dB",
                        status: plrStatus,
                        targetPage: 5,
                        navigateTo: $navigateTo
                    )

                    if let stereo = result.stereo {
                        MetricCard(
                            title: "Correlation",
                            value: String(format: "%.2f", stereo.averageCorrelation),
                            unit: "",
                            status: correlationStatus(stereo.averageCorrelation),
                            targetPage: 4,
                            navigateTo: $navigateTo
                        )
                    }

                    MetricCard(
                        title: "Crest Factor",
                        value: String(format: "%.1f", result.dynamics.averageCrestFactor),
                        unit: "dB",
                        status: .neutral,
                        targetPage: 5,
                        navigateTo: $navigateTo
                    )
                }
            }
            .padding()
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.metadata.fileName)
                .font(.title3.bold())
                .foregroundStyle(Color(hex: 0xE0E0E0))

            HStack(spacing: 16) {
                Text(formatSampleRate(result.metadata.sampleRate))
                Text(result.metadata.channelCount == 1 ? "Mono" : "Stereo")
                Text(formatDuration(result.metadata.duration))
            }
            .font(.caption)
            .foregroundStyle(Color(hex: 0x888888))
        }
    }

    private var loudnessStatus: MetricStatus {
        let lufs = result.loudness.integratedLUFS
        if lufs > -9 { return .error }
        if lufs > -11 { return .warning }
        return .pass
    }

    private var truePeakStatus: MetricStatus {
        let tp = result.truePeak.maxTruePeakDBTP
        if tp > -1.0 { return .error }
        if tp > -2.0 { return .warning }
        return .pass
    }

    private var plrStatus: MetricStatus {
        let plr = result.dynamics.plrDB
        if plr < 6 { return .warning }
        return .pass
    }

    private func correlationStatus(_ corr: Double) -> MetricStatus {
        if corr < 0 { return .error }
        if corr < 0.5 { return .warning }
        return .pass
    }

    private func formatSampleRate(_ rate: Double) -> String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : String(format: "%.0f Hz", rate)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

enum MetricStatus {
    case pass, warning, error, neutral

    var color: Color {
        switch self {
        case .pass: return Color(hex: 0x00CC66)
        case .warning: return Color(hex: 0xFFB800)
        case .error: return Color(hex: 0xFF3366)
        case .neutral: return Color(hex: 0x00D4FF)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let status: MetricStatus
    let targetPage: Int
    @Binding var navigateTo: Int

    var body: some View {
        Button {
            navigateTo = targetPage
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                    Spacer()
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(Color(hex: 0xE0E0E0))
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x888888))
                }
            }
            .padding(12)
            .background(Color(hex: 0x1A1A2E))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
