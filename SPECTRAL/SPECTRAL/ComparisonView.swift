import SwiftUI

struct ComparisonPillBar: View {
    @ObservedObject var stack: ComparisonStack

    var body: some View {
        if stack.files.count > 1 {
            VStack(spacing: 4) {
                if let warning = stack.alignmentWarning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(Color(hex: 0xFFB800))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: 0xFFB800).opacity(0.15))
                        .cornerRadius(6)
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
            .background(Color(hex: 0x1A1A2E).opacity(0.8))
        }
    }

    private func filePill(file: AnalysisResult, index: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: ComparisonStack.fileColors[index]))
                .frame(width: 8, height: 8)
            Text(file.metadata.fileName)
                .font(.caption2)
                .foregroundStyle(Color(hex: 0xE0E0E0))
                .lineLimit(1)
            Button {
                stack.remove(id: file.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: 0x888888))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: 0x333333))
        .cornerRadius(12)
        .onTapGesture {
            stack.promote(id: file.id)
        }
    }
}

struct ComparisonSummaryTable: View {
    let stack: ComparisonStack

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comparison")
                .font(.headline)
                .foregroundStyle(Color(hex: 0xE0E0E0))

            let deltas = stack.deltas()
            ForEach(deltas, id: \.fileId) { delta in
                VStack(alignment: .leading, spacing: 4) {
                    Text(delta.fileName)
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: 0xE0E0E0))

                    HStack(spacing: 12) {
                        deltaItem("LUFS", delta.deltaIntegratedLUFS)
                        deltaItem("TP", delta.deltaTruePeakDBTP)
                        deltaItem("LRA", delta.deltaLRA)
                        deltaItem("PLR", delta.deltaPLR)
                    }
                }
                .padding(8)
                .background(Color(hex: 0x1A1A2E))
                .cornerRadius(8)
            }
        }
    }

    private func deltaItem(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(hex: 0x888888))
            Text(String(format: "%+.1f", value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(value > 0 ? Color(hex: 0xFF3366) : (value < 0 ? Color(hex: 0x00CC66) : Color(hex: 0xE0E0E0)))
        }
    }
}
