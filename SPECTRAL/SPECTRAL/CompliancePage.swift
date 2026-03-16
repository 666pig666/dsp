import SwiftUI

struct CompliancePage: View {
    let result: AnalysisResult
    var comparisonStack: ComparisonStack? = nil
    @State private var selectedPreset: PlatformPreset

    init(result: AnalysisResult, comparisonStack: ComparisonStack? = nil) {
        self.result = result
        self.comparisonStack = comparisonStack
        _selectedPreset = State(initialValue: PlatformPreset.builtInPresets[0])
    }

    private var isComparison: Bool {
        (comparisonStack?.files.count ?? 0) > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Horizontal capsule preset selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlatformPreset.builtInPresets) { preset in
                            Button {
                                selectedPreset = preset
                            } label: {
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(selectedPreset.id == preset.id ? Theme.bg0 : Theme.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedPreset.id == preset.id ? Theme.accent : Theme.bg3)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.2), value: selectedPreset.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                if isComparison, let stack = comparisonStack {
                    multiFileComplianceGrid(stack: stack)
                } else {
                    // Single-file compliance rows card
                    VStack(spacing: 0) {
                        complianceHeader
                        Divider().background(Theme.bg4)

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

                        Divider().background(Theme.bg4)

                        complianceRow(
                            metric: "True Peak",
                            measured: result.truePeak.maxTruePeakDBTP,
                            target: selectedPreset.maxTruePeakDBTP,
                            tolerance: 0,
                            unit: "dBTP",
                            checkType: .belowThreshold
                        )
                    }
                    .background(Theme.bg2)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.bg4).frame(height: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                }
            }
            .padding()
        }
    }

    // MARK: - Multi-file grid

    private func multiFileComplianceGrid(stack: ComparisonStack) -> some View {
        let files = stack.files
        let preset = selectedPreset

        return VStack(spacing: 0) {
            // Column headers (file names)
            HStack(spacing: 0) {
                Text("METRIC")
                    .frame(width: 80, alignment: .leading)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(Array(files.enumerated()), id: \.element.id) { i, file in
                    let color = Theme.fileColor(i)
                    Text(String(file.metadata.fileName.prefix(10)))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().background(Theme.bg4)

            // Integrated row
            HStack(spacing: 0) {
                Text("Integrated")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 80, alignment: .leading)
                ForEach(Array(files.enumerated()), id: \.element.id) { i, file in
                    let val = file.loudness.integratedLUFS
                    let passed: Bool
                    if let target = preset.targetIntegratedLUFS, let tol = preset.targetIntegratedTolerance {
                        passed = abs(val - target) <= tol
                    } else {
                        passed = true
                    }
                    Text(String(format: "%.1f", val))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(passed ? Theme.pass : Theme.error)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Theme.bg4)

            // True Peak row
            HStack(spacing: 0) {
                Text("True Peak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 80, alignment: .leading)
                ForEach(Array(files.enumerated()), id: \.element.id) { i, file in
                    let val    = file.truePeak.maxTruePeakDBTP
                    let passed = val <= preset.maxTruePeakDBTP
                    Text(String(format: "%.1f", val))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(passed ? Theme.pass : Theme.error)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.bg2)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.bg4).frame(height: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    // MARK: - Header

    private var complianceHeader: some View {
        HStack {
            Text("METRIC").frame(width: 80, alignment: .leading)
            Text("MEAS").frame(width: 55, alignment: .trailing)
            Text("TARGET").frame(width: 55, alignment: .trailing)
            Text("DELTA").frame(width: 50, alignment: .trailing)
            Spacer()
            Text("STATUS").frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - No normalisation row

    private var noNormalisationRow: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Integrated")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 80, alignment: .leading)
                Text(String(format: "%.1f", result.loudness.integratedLUFS))
                    .frame(width: 55, alignment: .trailing)
                Text("—")
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(Theme.textSecondary)
                Text("—")
                    .frame(width: 50, alignment: .trailing)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("N/A")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)

            // Empty bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.bg4)
                .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Check type

    private enum CheckType {
        case withinTolerance
        case belowThreshold
    }

    // MARK: - Compliance row with progress bar

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
        let fillFraction: Double

        switch checkType {
        case .withinTolerance:
            passed = abs(delta) <= tolerance
            let overshoot = max(0, abs(delta) - tolerance)
            fillFraction = max(0, min(1, 1.0 - overshoot / 6.0))
        case .belowThreshold:
            passed = measured <= target
            let overshoot = max(0, measured - target)
            fillFraction = max(0, min(1, 1.0 - overshoot / 3.0))
        }

        let barColor: Color = passed ? Theme.pass : Theme.error
        let statusText = passed ? "PASS" : "FAIL"

        return VStack(spacing: 6) {
            HStack {
                Text(metric)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 80, alignment: .leading)
                Text(String(format: "%.1f", measured))
                    .frame(width: 55, alignment: .trailing)
                Text(String(format: "%.1f", target))
                    .frame(width: 55, alignment: .trailing)
                    .foregroundStyle(Theme.textSecondary)
                Text(String(format: "%+.1f", delta))
                    .frame(width: 50, alignment: .trailing)
                    .foregroundStyle(passed ? Theme.pass : Theme.error)
                Spacer()
                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(barColor)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.bg4)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * fillFraction, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
