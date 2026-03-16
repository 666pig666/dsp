import SwiftUI

struct ComparisonPillBar: View {
    @ObservedObject var stack: ComparisonStack

    var body: some View {
        if stack.files.count > 1 {
            VStack(spacing: 4) {
                if let warning = stack.alignmentWarning {
                    Text(warning)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.warning.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(stack.files.enumerated()), id: \.element.id) { idx, file in
                            filePill(file: file, index: idx)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 4)
            .background(Theme.bg3.opacity(0.8))
        }
    }

    private func filePill(file: AnalysisResult, index: Int) -> some View {
        let color = Theme.fileColor(index)
        let isPrimary = index == 0

        return HStack(spacing: 4) {
            // Glow dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 4)

            Text(String(file.metadata.fileName.prefix(20)))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Button {
                stack.remove(id: file.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.bg3)
        .overlay(
            Capsule()
                .stroke(isPrimary ? Theme.accent : Color.clear, lineWidth: 1)
        )
        .clipShape(Capsule())
        .onTapGesture {
            stack.promote(id: file.id)
        }
    }
}

struct ComparisonSummaryTable: View {
    @ObservedObject var stack: ComparisonStack

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMPARISON")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)

            let deltas = stack.deltas()
            ForEach(deltas, id: \.fileId) { delta in
                VStack(alignment: .leading, spacing: 4) {
                    Text(delta.fileName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    HStack(spacing: 12) {
                        deltaItem("LUFS", delta.deltaIntegratedLUFS, metric: .lufs)
                        deltaItem("TP",   delta.deltaTruePeakDBTP,   metric: .truePeak)
                        deltaItem("LRA",  delta.deltaLRA,            metric: .lra)
                        deltaItem("PLR",  delta.deltaPLR,            metric: .plr)
                    }
                }
                .padding(10)
                .background(Theme.bg2)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.bg4).frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Delta items with metric-aware coloring

    private func deltaItem(_ label: String, _ value: Double, metric: DeltaMetric) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Text(String(format: "%+.1f", value))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(deltaColor(value, metric: metric))
        }
    }

    private enum DeltaMetric {
        case lufs, truePeak, lra, plr
    }

    /// Metric-directional delta coloring per spec §3G.
    private func deltaColor(_ value: Double, metric: DeltaMetric) -> Color {
        if abs(value) < 0.05 { return Theme.textTertiary }
        switch metric {
        case .lufs:    return value > 0 ? Theme.warning : Theme.textTertiary
        case .truePeak: return value > 0 ? Theme.error  : Theme.pass
        case .lra:     return Theme.textTertiary
        case .plr:     return value > 0 ? Theme.pass    : Theme.warning
        }
    }
}
