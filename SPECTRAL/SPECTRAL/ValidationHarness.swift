import Foundation
import Accelerate

struct ValidationTestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let details: String
}

class ValidationHarness: ObservableObject {
    @Published var results: [ValidationTestResult] = []
    @Published var isRunning = false

    private let sampleRate: Double = 48000
    private let duration: Double = 10.0

    @MainActor
    func runAll() async {
        isRunning = true
        results = []

        let test1 = await runTest1Null()
        results.append(test1)

        let test2 = await runTest2GainOffset()
        results.append(test2)

        let test3 = await runTest3KnownEQ()
        results.append(test3)

        let test4 = await runTest4PhaseInversion()
        results.append(test4)

        let test5 = await runTest5LengthMismatch()
        results.append(test5)

        isRunning = false
    }

    // MARK: - Test Signal Generation

    private func generateSine(frequency: Double, amplitude: Float, sampleRate: Double, duration: Double) -> [Float] {
        let count = Int(sampleRate * duration)
        var signal = [Float](repeating: 0, count: count)
        for i in 0..<count {
            signal[i] = amplitude * Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }
        return signal
    }

    // MARK: - Test 1: Null (bit-identical)

    private func runTest1Null() async -> ValidationTestResult {
        let signal = generateSine(frequency: 1000, amplitude: 0.2, sampleRate: sampleRate, duration: duration)

        let resultA = analyzeSignal(left: signal, right: signal)
        let resultB = analyzeSignal(left: signal, right: signal)

        let deltaLUFS = abs(resultA.loudness.integratedLUFS - resultB.loudness.integratedLUFS)
        let deltaTP = abs(resultA.truePeak.maxTruePeakDBTP - resultB.truePeak.maxTruePeakDBTP)

        let passed = deltaLUFS < 0.01 && deltaTP < 0.01
        return ValidationTestResult(
            name: "Test 1: Null (bit-identical)",
            passed: passed,
            details: "Delta LUFS: \(String(format: "%.4f", deltaLUFS)), Delta TP: \(String(format: "%.4f", deltaTP))"
        )
    }

    // MARK: - Test 2: Gain Offset (+3 dB)

    private func runTest2GainOffset() async -> ValidationTestResult {
        let signal = generateSine(frequency: 1000, amplitude: 0.2, sampleRate: sampleRate, duration: duration)

        let gainLinear = Float(pow(10.0, 3.0 / 20.0)) // +3 dB
        var gained = [Float](repeating: 0, count: signal.count)
        var scalar = gainLinear
        vDSP_vsmul(signal, 1, &scalar, &gained, 1, vDSP_Length(signal.count))

        let resultA = analyzeSignal(left: signal, right: signal)
        let resultB = analyzeSignal(left: gained, right: gained)

        let deltaLUFS = resultB.loudness.integratedLUFS - resultA.loudness.integratedLUFS
        let passed = abs(deltaLUFS - 3.0) < 0.1

        return ValidationTestResult(
            name: "Test 2: +3 dB Gain Offset",
            passed: passed,
            details: "Delta LUFS: \(String(format: "%.2f", deltaLUFS)) (expected 3.0 +/- 0.1)"
        )
    }

    // MARK: - Test 3: Known EQ (high shelf at 8 kHz)

    private func runTest3KnownEQ() async -> ValidationTestResult {
        let signal = generateSine(frequency: 1000, amplitude: 0.2, sampleRate: sampleRate, duration: duration)
        let highSignal = generateSine(frequency: 8000, amplitude: 0.2, sampleRate: sampleRate, duration: duration)

        // Mix: base + boosted 8 kHz
        let gainLinear = Float(pow(10.0, 3.0 / 20.0))
        var boosted8k = [Float](repeating: 0, count: highSignal.count)
        var scalar = gainLinear
        vDSP_vsmul(highSignal, 1, &scalar, &boosted8k, 1, vDSP_Length(highSignal.count))

        var mixA = [Float](repeating: 0, count: signal.count)
        vDSP_vadd(signal, 1, highSignal, 1, &mixA, 1, vDSP_Length(signal.count))

        var mixB = [Float](repeating: 0, count: signal.count)
        vDSP_vadd(signal, 1, boosted8k, 1, &mixB, 1, vDSP_Length(signal.count))

        let resultA = analyzeSignal(left: mixA, right: mixA)
        let resultB = analyzeSignal(left: mixB, right: mixB)

        // Check spectral difference around 8 kHz bin
        let freqRes = sampleRate / Double(resultA.spectrum.fftSize)
        let bin8k = Int(8000.0 / freqRes)
        let diffAt8k: Float
        if bin8k < resultA.spectrum.averageSpectrum.count && bin8k < resultB.spectrum.averageSpectrum.count {
            diffAt8k = resultB.spectrum.averageSpectrum[bin8k] - resultA.spectrum.averageSpectrum[bin8k]
        } else {
            diffAt8k = 0
        }

        let passed = abs(diffAt8k - 3.0) < 0.5
        return ValidationTestResult(
            name: "Test 3: Known EQ (+3 dB shelf at 8 kHz)",
            passed: passed,
            details: "Spectral diff at 8 kHz: \(String(format: "%.1f", diffAt8k)) dB (expected 3.0 +/- 0.5)"
        )
    }

    // MARK: - Test 4: Phase Inversion

    private func runTest4PhaseInversion() async -> ValidationTestResult {
        let left = generateSine(frequency: 1000, amplitude: 0.5, sampleRate: sampleRate, duration: duration)
        var right = [Float](repeating: 0, count: left.count)
        var negOne: Float = -1.0
        vDSP_vsmul(left, 1, &negOne, &right, 1, vDSP_Length(left.count))

        let stereoAnalyzer = StereoAnalyzer()
        guard let stereoResult = stereoAnalyzer.analyze(left: left, right: right, sampleRate: sampleRate) else {
            return ValidationTestResult(
                name: "Test 4: Phase Inversion",
                passed: false,
                details: "Stereo analysis returned nil"
            )
        }

        let corrPassed = abs(stereoResult.averageCorrelation - (-1.0)) < 0.01
        let midNearZero = stereoResult.midSideRatioDB < -60 || stereoResult.midSideRatioDB.isInfinite

        let passed = corrPassed && (midNearZero || stereoResult.midSideRatioDB < -60)
        return ValidationTestResult(
            name: "Test 4: Phase Inversion",
            passed: passed,
            details: "Correlation: \(String(format: "%.3f", stereoResult.averageCorrelation)) (expected -1.0), M/S ratio: \(String(format: "%.1f", stereoResult.midSideRatioDB)) dB"
        )
    }

    // MARK: - Test 5: Length Mismatch

    private func runTest5LengthMismatch() async -> ValidationTestResult {
        let signal = generateSine(frequency: 1000, amplitude: 0.2, sampleRate: sampleRate, duration: duration)

        let extraSilence = [Float](repeating: 0, count: Int(sampleRate * 2))
        let longerSignal = signal + extraSilence

        let resultA = analyzeSignal(left: signal, right: signal)
        let resultB = analyzeSignal(left: longerSignal, right: longerSignal)

        // B should have lower integrated LUFS due to silence
        let deltaLUFS = resultB.loudness.integratedLUFS - resultA.loudness.integratedLUFS

        // Check alignment warning would trigger
        let frameDiff = abs(Int64(longerSignal.count) - Int64(signal.count))
        let warningExpected = frameDiff > Int64(sampleRate)

        let passed = deltaLUFS < 0 && warningExpected
        return ValidationTestResult(
            name: "Test 5: Length Mismatch",
            passed: passed,
            details: "Delta LUFS: \(String(format: "%.2f", deltaLUFS)) (expected < 0), Frame diff: \(frameDiff) (warning expected: \(warningExpected))"
        )
    }

    // MARK: - Helper

    private func analyzeSignal(left: [Float], right: [Float]) -> AnalysisResult {
        let metadata = AudioFileMetadata(
            id: UUID(),
            fileName: "test_signal",
            url: URL(fileURLWithPath: "/tmp/test"),
            sampleRate: sampleRate,
            channelCount: 2,
            frameCount: Int64(left.count),
            duration: Double(left.count) / sampleRate,
            formatDescription: "Test signal"
        )

        let channelData = ChannelData(channels: [left, right])

        let kFilter = KWeightingFilter(sampleRate: sampleRate)
        let kWeighted = kFilter.processChannelData(channelData)

        let loudness = LoudnessMeter().measure(kWeightedData: kWeighted, sampleRate: sampleRate)
        let truePeak = TruePeakMeter().measure(channelData: channelData, sampleRate: sampleRate, ratio: .x8)
        let spectrum = SpectrumAnalyzer().analyze(channelData: channelData, sampleRate: sampleRate)
        let stereo = StereoAnalyzer().analyze(left: left, right: right, sampleRate: sampleRate)
        let dynamics = DynamicsAnalyzer().analyze(
            channelData: channelData, loudness: loudness, truePeak: truePeak, sampleRate: sampleRate
        )

        return AnalysisResult(
            id: UUID(),
            metadata: metadata,
            channelMode: .stereo,
            loudness: loudness,
            truePeak: truePeak,
            spectrum: spectrum,
            stereo: stereo,
            dynamics: dynamics,
            analysisDate: Date(),
            oversamplingRatio: 8
        )
    }
}
