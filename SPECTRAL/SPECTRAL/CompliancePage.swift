import SwiftUI

struct CompliancePage: View {
    let result: AnalysisResult
    @State private var selectedPreset: PlatformPreset

    init(result: AnalysisResult) {
        self.result = result
        _selectedPreset = State(initialValue: PlatformPreset.builtInPresets[0])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Preset selector
                Picker("Platform", selection: $selectedPreset) {
                    ForEach(PlatformPreset.builtInPresets) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color(hex: 0x00D4FF))

                // Compliance grid
                VStack(spacing: 0) {
                    complianceHeader
                    Divider().background(Color(hex: 0x333333))
                    if let lufsTarget = selectedPreset.targetIntegratedLUFS,
                       let tolerance = selectedPreset.targetIntegratedTolerance {
                        complianceRow(
                            metric: "Integrated",
                            measured: result.loudness.integratedLUFS,
                            target: lufsTarget,
                            tolerance: tolerance,
                            unit: "LUFS",
                            checkType: .withinTolerance
                        )
                    } else {
                        noNormalisationRow
                    }
                    Divider().background(Color(hex: 0x333333))
                    complianceRow(
                        metric: "True Peak",
                        measured: result.truePeak.maxTruePeakDBTP,
                        target: selectedPreset.maxTruePeakDBTP,
                        tolerance: 0,
                        unit: "dBTP",
                        checkType: .belowThreshold
                    )
                }
                .background(Color(hex: 0x1A1A2E))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    private var complianceHeader: some View {
        HStack {
            Text("Metric").frame(width: 80, alignment: .leading)
            Text("Measured").frame(width: 70, alignment: .trailing)
            Text("Target").frame(width: 70, alignment: .trailing)
            Text("Delta").frame(width: 60, alignment: .trailing)
            Text("").frame(width: 30)
        }
        .font(.caption2.bold())
        .foregroundStyle(Color(hex: 0x888888))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // Shown for platforms with no loudness normalisation (SoundCloud, Bandcamp).
    private var noNormalisationRow: some View {
        HStack {
            Text("Integrated")
                .frame(width: 80, alignment: .leading)
            Text(String(format: "%.1f", result.loudness.integratedLUFS))
                .frame(width: 70, alignment: .trailing)
            Text("—")
                .frame(width: 70, alignment: .trailing)
            Text("—")
                .frame(width: 60, alignment: .trailing)
            Image(systemName: "minus.circle")
                .foregroundStyle(Color(hex: 0x888888))
                .frame(width: 30)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Color(hex: 0x888888))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private enum CheckType {
        case withinTolerance
        case belowThreshold
    }

    private func complianceRow(
        metric: String,
        measured: Double,
        target: Double,
        tolerance: Double,
        unit: String,
        checkType: CheckType
    ) -> some View {
        let delta = measured - target
        let passed: Bool
        switch checkType {
        case .withinTolerance:
            passed = abs(delta) <= tolerance
        case .belowThreshold:
            passed = measured <= target
        }

        return HStack {
            Text(metric)
                .frame(width: 80, alignment: .leading)
            Text(String(format: "%.1f", measured))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.1f", target))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%+.1f", delta))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(passed ? Color(hex: 0x00CC66) : Color(hex: 0xFF3366))
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? Color(hex: 0x00CC66) : Color(hex: 0xFF3366))
                .frame(width: 30)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Color(hex: 0xE0E0E0))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
