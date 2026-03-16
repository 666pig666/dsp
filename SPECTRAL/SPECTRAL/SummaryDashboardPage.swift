import SwiftUI
import UIKit

struct SummaryDashboardPage: View {
    let result: AnalysisResult
    @Binding var navigateTo: Int
    var comparisonStack: ComparisonStack? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                metadataBar

                if let stack = comparisonStack, stack.files.count > 1 {
                    MetricAwareDeltaTable(stack: stack)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                LazyVGrid(columns: columns, spacing: 10) {
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
                .padding(16)
            }
        }
        .background(Theme.bg1)
    }

    // MARK: - Metadata bar

    private var metadataBar: some View {
        HStack(spacing: 0) {
            Text(result.metadata.fileName)
                .foregroundStyle(Theme.textPrimary)
            Text(" · \(formatSampleRate(result.metadata.sampleRate))")
            Text(" · \(result.metadata.channelCount == 1 ? "Mono" : "Stereo")")
            Text(" · \(formatDuration(result.metadata.duration))")
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg0)
    }

    // MARK: - Status helpers

    private var loudnessStatus: MetricStatus {
        let v = result.loudness.integratedLUFS
        if v > -9  { return .error }
        if v > -11 { return .warning }
        return .pass
    }

    private var truePeakStatus: MetricStatus {
        let v = result.truePeak.maxTruePeakDBTP
        if v > -1.0 { return .error }
        if v > -2.0 { return .warning }
        return .pass
    }

    private var plrStatus: MetricStatus {
        result.dynamics.plrDB < 6 ? .warning : .pass
    }

    private func correlationStatus(_ c: Double) -> MetricStatus {
        if c < 0   { return .error }
        if c < 0.5 { return .warning }
        return .pass
    }

    // MARK: - Formatters

    private func formatSampleRate(_ rate: Double) -> String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : String(format: "%.0f Hz", rate)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - MetricAwareDeltaTable

/// Comparison table with per-metric directional delta coloring.
struct MetricAwareDeltaTable: View {
    @ObservedObject var stack: ComparisonStack

    var body: some View {
        let deltas = stack.deltas()
        guard !deltas.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text("COMPARISON")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)

                // Header row
                HStack(spacing: 0) {
                    Text("FILE").frame(width: 100, alignment: .leading)
                    Spacer()
                    Group {
                        Text("LUFS").frame(width: 42, alignment: .trailing)
                        Text("TP").frame(width: 42, alignment: .trailing)
                        Text("LRA").frame(width: 42, alignment: .trailing)
                        Text("PLR").frame(width: 42, alignment: .trailing)
                        Text("CORR").frame(width: 42, alignment: .trailing)
                        Text("CREST").frame(width: 42, alignment: .trailing)
                        Text("RMS").frame(width: 42, alignment: .trailing)
                    }
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)

                Divider().background(Theme.bg4)

                ForEach(Array(deltas.enumerated()), id: \.element.fileId) { i, delta in
                    let color = Theme.fileColor(i + 1)
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 6, height: 6)
                            Text(String(delta.fileName.prefix(12)))
                                .lineLimit(1)
                        }
                        .frame(width: 100, alignment: .leading)

                        Spacer()

                        Group {
                            deltaCell(delta.deltaIntegratedLUFS, metric: .lufs)
                            deltaCell(delta.deltaTruePeakDBTP,   metric: .truePeak)
                            deltaCell(delta.deltaLRA,            metric: .lra)
                            deltaCell(delta.deltaPLR,            metric: .plr)
                            deltaCell(delta.deltaCorrelation,    metric: .correlation)
                            deltaCell(delta.deltaCrestFactor,    metric: .crestFactor)
                            deltaCell(delta.deltaRMS,            metric: .rms)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))

                    if i < deltas.count - 1 {
                        Divider().background(Theme.bg4)
                    }
                }
            }
            .padding(12)
            .background(Theme.bg2)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.bg4).frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    private enum MetricKind {
        case lufs, truePeak, lra, plr, correlation, crestFactor, rms
    }

    private func deltaCell(_ value: Double, metric: MetricKind) -> some View {
        Text(String(format: "%+.1f", value))
            .frame(width: 42, alignment: .trailing)
            .foregroundStyle(deltaColor(value, metric: metric))
    }

    /// Metric-directional delta coloring per spec §3E.
    private func deltaColor(_ value: Double, metric: MetricKind) -> Color {
        if abs(value) < 0.05 { return Theme.textTertiary }
        switch metric {
        case .lufs:        return value > 0 ? Theme.warning  : Theme.textTertiary
        case .truePeak:    return value > 0 ? Theme.error    : Theme.pass
        case .lra:         return Theme.textTertiary
        case .plr:         return value > 0 ? Theme.pass     : Theme.warning
        case .crestFactor: return value > 0 ? Theme.pass     : Theme.warning
        case .correlation: return value > 0 ? Theme.textTertiary : Theme.warning
        case .rms:         return value > 0 ? Theme.warning  : Theme.textTertiary
        }
    }
}

// MARK: - MetricStatus

enum MetricStatus {
    case pass, warning, error, neutral

    var color: Color {
        switch self {
        case .pass:    return Theme.pass
        case .warning: return Theme.warning
        case .error:   return Theme.error
        case .neutral: return Theme.accent
        }
    }

    var label: String {
        switch self {
        case .pass:    return "Pass"
        case .warning: return "Warn"
        case .error:   return "Fail"
        case .neutral: return "—"
        }
    }
}

// MARK: - MetricCard

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let status: MetricStatus
    let targetPage: Int
    @Binding var navigateTo: Int

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            navigateTo = targetPage
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Section header — uppercase, tracked, tertiary
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)

                Spacer(minLength: 8)

                // Hero value — SF Mono 32pt bold
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                // Unit label
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 10)

                // Status dot + label — bottom-right aligned
                HStack(spacing: 4) {
                    Spacer()
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                        .shadow(color: status.color.opacity(0.6), radius: 4)
                    Text(status.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(status.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg2)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.bg4)
                    .frame(height: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
