import SwiftUI
import Charts

struct SpectrumPage: View {
    let result: AnalysisResult
    var comparisonStack: ComparisonStack? = nil

    @State private var showWaterfall = false
    @State private var showDifference = false
    @State private var showOctaveBands = false
    @State private var showThirdOctave = false

    private var isComparison: Bool {
        (comparisonStack?.files.count ?? 0) > 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Mode toggle row
                HStack(spacing: 8) {
                    toggleButton("Waterfall", isOn: $showWaterfall)
                    if isComparison {
                        toggleButton("Difference", isOn: $showDifference)
                    }
                }

                // Main chart — waterfall OR spectrum
                if showWaterfall {
                    let frames = result.spectrum.waterfallFrames
                    if !frames.isEmpty {
                        WaterfallView(frames: frames)
                            .frame(height: 250)
                    }
                } else {
                    spectrumCanvasChart
                        .frame(height: 250)
                }

                // Band toggles
                HStack(spacing: 8) {
                    toggleButton("Octave Bands", isOn: $showOctaveBands)
                    toggleButton("1/3 Octave",   isOn: $showThirdOctave)
                }

                if showOctaveBands {
                    bandCanvasChart(bands: result.spectrum.octaveBands)
                        .frame(height: 200)
                }
                if showThirdOctave {
                    bandCanvasChart(bands: result.spectrum.thirdOctaveBands)
                        .frame(height: 200)
                }

                spectralBalanceView
            }
            .padding()
        }
    }

    // MARK: - Spectrum canvas chart

    @ViewBuilder
    private var spectrumCanvasChart: some View {
        if isComparison, let stack = comparisonStack {
            if showDifference {
                diffSpectrumChart(stack: stack)
            } else {
                overlaySpectrumChart(stack: stack)
            }
        } else {
            singleSpectrumChart
        }
    }

    private var singleSpectrumChart: some View {
        let freq = result.spectrum.frequencyAxis.map { Double($0) }
        let avg  = result.spectrum.averageSpectrum.map { Double($0) }
        let peak = result.spectrum.peakHoldSpectrum.map { Double($0) }

        let avgSeries = CanvasChartSeries(
            label:  "Average",
            color:  Theme.chartSpecAvg,
            values: avg,
            xValues: freq,
            lineWidth: 1.5,
            gradientFill: true
        )
        let peakSeries = CanvasChartSeries(
            label:  "Peak",
            color:  Theme.chartSpecPeak,
            values: peak,
            xValues: freq,
            lineWidth: 1.0,
            opacity: 0.7
        )
        return CanvasLineChart(
            series: [avgSeries, peakSeries],
            yDomain: -100...0,
            xDomain: 20...20_000,
            logScaleX: true,
            legendItems: [("Average", Theme.chartSpecAvg), ("Peak", Theme.chartSpecPeak)]
        )
    }

    private func overlaySpectrumChart(stack: ComparisonStack) -> some View {
        var allSeries = [CanvasChartSeries]()
        var legendItems = [(String, Color)]()

        for (i, file) in stack.files.enumerated() {
            let color = Theme.fileColor(i)
            let freq  = file.spectrum.frequencyAxis.map { Double($0) }
            let avg   = file.spectrum.averageSpectrum.map { Double($0) }
            let name  = String(file.metadata.fileName.prefix(16))
            allSeries.append(CanvasChartSeries(
                label: name,
                color: color,
                values: avg,
                xValues: freq,
                lineWidth: i == 0 ? 1.5 : 1.0,
                opacity: i == 0 ? 1.0 : 0.8,
                gradientFill: i == 0
            ))
            legendItems.append((name, color))
        }
        return CanvasLineChart(
            series: allSeries,
            yDomain: -100...0,
            xDomain: 20...20_000,
            logScaleX: true,
            legendItems: legendItems
        )
    }

    private func diffSpectrumChart(stack: ComparisonStack) -> some View {
        guard let primary = stack.files.first else { return AnyView(EmptyView()) }
        let primaryAvg = primary.spectrum.averageSpectrum
        let freq = primary.spectrum.frequencyAxis.map { Double($0) }

        var allSeries = [CanvasChartSeries]()
        var legendItems = [(String, Color)]()

        for (i, file) in stack.files.dropFirst().enumerated() {
            let color = Theme.fileColor(i + 1)
            let name  = String(file.metadata.fileName.prefix(16))
            let diff: [Double] = zip(file.spectrum.averageSpectrum, primaryAvg)
                .map { Double($0) - Double($1) }

            allSeries.append(CanvasChartSeries(
                label: name,
                color: color,
                values: diff,
                xValues: freq,
                lineWidth: 1.2
            ))
            legendItems.append((name, color))
        }

        // Auto-scale ±6 dB or wider
        let maxDelta = allSeries.flatMap(\.values).map { abs($0) }.max() ?? 6
        let range    = max(6.0, maxDelta) * 1.1

        return AnyView(
            CanvasLineChart(
                series: allSeries,
                yDomain: -range...range,
                xDomain: 20...20_000,
                logScaleX: true,
                zeroLine: true,
                legendItems: legendItems
            )
        )
    }

    // MARK: - Band chart (Canvas bars)

    private func bandCanvasChart(bands: [BandEnergy]) -> some View {
        let minDB = (bands.map(\.energyDB).min() ?? -60) - 3
        let maxDB = (bands.map(\.energyDB).max() ?? 0)  + 3
        let yDomain = minDB...maxDB

        return Canvas { context, size in
            // Background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [Theme.chartBgCenter, Theme.chartBgEdge]),
                    center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.65
                )
            )
            context.stroke(
                Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)),
                with: .color(Theme.chartBorder), lineWidth: 1
            )

            guard !bands.isEmpty else { return }

            let count = bands.count
            let totalWidth = size.width
            let barSpacing: CGFloat = 2
            let barWidth = (totalWidth - CGFloat(count + 1) * barSpacing) / CGFloat(count)
            let yRange = yDomain.upperBound - yDomain.lowerBound

            let mapY: (Double) -> CGFloat = { val in
                let t = (val - yDomain.lowerBound) / yRange
                return CGFloat(1.0 - t) * size.height
            }

            let zeroY = mapY(0)

            for (i, band) in bands.enumerated() {
                let x = barSpacing + CGFloat(i) * (barWidth + barSpacing)
                let y = mapY(band.energyDB)
                let barRect = CGRect(
                    x: x,
                    y: min(y, zeroY),
                    width: barWidth,
                    height: abs(y - zeroY)
                )
                context.fill(
                    Path(RoundedRectangle(cornerRadius: 2).path(in: barRect)),
                    with: .color(Theme.chartSpecAvg.opacity(0.8))
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Spectral balance

    private var spectralBalanceView: some View {
        let balance = result.spectrum.spectralBalance
        let bands: [(String, Double)] = [
            ("Sub",      balance.subDB),
            ("Low",      balance.lowDB),
            ("Low-Mid",  balance.lowMidDB),
            ("High-Mid", balance.highMidDB),
            ("High",     balance.highDB)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            Text("SPECTRAL BALANCE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)

            ForEach(bands, id: \.0) { name, db in
                HStack {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 70, alignment: .leading)

                    GeometryReader { geo in
                        let normalized = max(0, min(1, (db + 30) / 30))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * normalized, height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 16)

                    Text(String(format: "%.1f dB", db))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(Theme.bg2)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.bg4).frame(height: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    // MARK: - Toggle button

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
}

// Index-based identity — stable across SwiftUI re-renders.
struct SpectrumPoint: Identifiable {
    let index: Int
    let frequency: Double
    let level: Double
    let series: String
    var id: Int { index }
}
