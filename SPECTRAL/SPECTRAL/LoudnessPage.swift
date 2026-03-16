import SwiftUI

struct LoudnessPage: View {
    let result: AnalysisResult
    var comparisonStack: ComparisonStack? = nil

    @State private var showDelta = false

    private var isComparison: Bool {
        (comparisonStack?.files.count ?? 0) > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Primary readout — hero metric
                VStack(spacing: 4) {
                    Text("INTEGRATED LOUDNESS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", result.loudness.integratedLUFS))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.4), value: result.loudness.integratedLUFS)
                        Text("LUFS")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                // Secondary readouts
                HStack(spacing: 20) {
                    readout("Momentary Max", String(format: "%.1f LUFS", result.loudness.momentaryMaxLUFS))
                    readout("Short-term Max", String(format: "%.1f LUFS", result.loudness.shortTermMaxLUFS))
                    readout("LRA", String(format: "%.1f LU", result.loudness.loudnessRangeLU))
                }
                .frame(maxWidth: .infinity)

                // Delta toggle in comparison mode
                if isComparison {
                    HStack(spacing: 8) {
                        toggleButton("Delta", isOn: $showDelta)
                    }
                }

                if !result.loudness.momentaryTimeSeries.isEmpty {
                    loudnessChart
                        .frame(height: 250)
                }
            }
            .padding()
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Loudness chart

    private var loudnessChart: some View {
        if isComparison, let stack = comparisonStack {
            return AnyView(comparisonLoudnessChart(stack: stack))
        } else {
            return AnyView(singleLoudnessChart)
        }
    }

    private var singleLoudnessChart: some View {
        let hopSec = result.loudness.blockDurationMs / 1000.0
        let maxPts = 600

        let momentaryVals = downsample(result.loudness.momentaryTimeSeries, maxPoints: maxPts)
            .map { max($0.value, -70) }
        let momentaryTimes = downsample(result.loudness.momentaryTimeSeries, maxPoints: maxPts)
            .map { $0.time * hopSec }

        let shortTermVals = downsample(result.loudness.shortTermTimeSeries, maxPoints: maxPts)
            .map { max($0.value, -70) }
        let shortTermTimes = downsample(result.loudness.shortTermTimeSeries, maxPoints: maxPts)
            .map { $0.time }

        let yLow = (momentaryVals + shortTermVals).min().map { min($0, -70.0) } ?? -70.0
        let yDomain = yLow...0.0

        let momentarySeries = CanvasChartSeries(
            label: "Momentary", color: Theme.chartMomentary,
            values: momentaryVals, xValues: momentaryTimes,
            lineWidth: 1.0, opacity: 0.5, dashed: true
        )
        let shortTermSeries = CanvasChartSeries(
            label: "Short-term", color: Theme.chartShortTerm,
            values: shortTermVals, xValues: shortTermTimes,
            lineWidth: 1.5, gradientFill: true
        )
        let integratedRef = CanvasReferenceLine(
            y: result.loudness.integratedLUFS,
            color: Theme.chartIntegrated,
            dashed: true
        )
        return CanvasLineChart(
            series: [momentarySeries, shortTermSeries],
            yDomain: yDomain,
            referenceLines: [integratedRef],
            legendItems: [
                ("Momentary",  Theme.chartMomentary),
                ("Short-term", Theme.chartShortTerm),
                ("Integrated", Theme.chartIntegrated)
            ]
        )
    }

    private func comparisonLoudnessChart(stack: ComparisonStack) -> some View {
        var allSeries  = [CanvasChartSeries]()
        var refLines   = [CanvasReferenceLine]()
        var legendItems = [(String, Color)]()
        var allVals    = [Double]()
        let maxPts     = 600

        for (i, file) in stack.files.enumerated() {
            let color = Theme.fileColor(i)
            let name  = String(file.metadata.fileName.prefix(16))
            let series = file.loudness.shortTermTimeSeries
            guard !series.isEmpty else { continue }

            if showDelta && i > 0, let primary = stack.files.first {
                // Delta mode: B-A over time
                let primSeries = primary.loudness.shortTermTimeSeries
                let count = min(series.count, primSeries.count)
                let maxIdx = min(count, maxPts)
                let step = max(1.0, Double(count - 1) / Double(maxPts - 1))

                var diffVals = [Double]()
                var diffTimes = [Double]()
                for j in 0..<maxIdx {
                    let idx = min(Int(Double(j) * step), count - 1)
                    diffVals.append(series[idx] - primSeries[idx])
                    diffTimes.append(Double(idx))
                }
                allSeries.append(CanvasChartSeries(
                    label: name, color: color, values: diffVals,
                    xValues: diffTimes, lineWidth: 1.2
                ))
                allVals += diffVals
            } else {
                let count  = series.count
                let step   = max(1.0, Double(count - 1) / Double(maxPts - 1))
                let maxIdx = min(count, maxPts)
                let vals  = (0..<maxIdx).map { j in
                    max(series[min(Int(Double(j) * step), count - 1)], -70.0)
                }
                let times = (0..<maxIdx).map { j -> Double in
                    Double(min(Int(Double(j) * step), count - 1))
                }
                allSeries.append(CanvasChartSeries(
                    label: name, color: color, values: vals,
                    xValues: times,
                    lineWidth: i == 0 ? 1.5 : 1.0,
                    opacity: i == 0 ? 1.0 : 0.8,
                    gradientFill: i == 0
                ))
                allVals += vals
                refLines.append(CanvasReferenceLine(
                    y: file.loudness.integratedLUFS, color: color, dashed: true
                ))
            }
            legendItems.append((name, color))
        }

        if showDelta {
            let range = max(6.0, (allVals.map { abs($0) }.max() ?? 6.0)) * 1.1
            return AnyView(CanvasLineChart(
                series: allSeries,
                yDomain: -range...range,
                zeroLine: true,
                referenceLines: [],
                legendItems: legendItems
            ))
        } else {
            let yLow = (allVals.min() ?? -70.0)
            return AnyView(CanvasLineChart(
                series: allSeries,
                yDomain: yLow...0,
                referenceLines: refLines,
                legendItems: legendItems
            ))
        }
    }

    // MARK: - Helpers

    private func toggleButton(_ label: String, isOn: Binding<Bool>) -> some View {
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

    private func downsample(_ series: [Double], maxPoints: Int) -> [(time: Double, value: Double)] {
        guard series.count > maxPoints else {
            return series.enumerated().map { (time: Double($0.offset), value: $0.element) }
        }
        let step = Double(series.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { i in
            let idx = min(Int(Double(i) * step), series.count - 1)
            return (time: Double(idx), value: series[idx])
        }
    }
}

// Index-based identity — stable across SwiftUI re-renders.
struct LoudnessPoint: Identifiable {
    let index: Int
    let time: Double
    let value: Double
    let series: String
    var id: Int { index }
}
