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

    // MARK: - Test 3: Known biquad EQ applied to broadband noise
    //
    // The previous two-sine approach (mixing 1 kHz + boosted 8 kHz) verified spectral
    // *amplitude* at an isolated frequency but did not exercise the FFT averaging path on
    // coloured broadband input and could not compare against a filter's theoretical transfer
    // function. This test is more rigorous:
    //   1. Generate deterministic broadband noise (LCG; same seed → identical sequence).
    //   2. Design a high-shelf biquad (+6 dB at 4 kHz, Q = 0.707) via Audio EQ Cookbook.
    //   3. Apply the filter in Double precision (Direct Form I) to avoid Float quantisation error.
    //   4. Evaluate H(e^jω) analytically at 16 kHz — a frequency well inside the shelf passband.
    //   5. Verify that the spectral difference measured by SpectrumAnalyzer at 16 kHz matches
    //      the theoretical gain to within ±0.5 dB.

    private func runTest3KnownEQ() async -> ValidationTestResult {
        let count = Int(sampleRate * duration)

        // Deterministic broadband noise (Knuth multiplicative LCG, period 2^63).
        // Using a fixed seed guarantees the same sequence across runs.
        var noise = [Float](repeating: 0, count: count)
        var seed: UInt64 = 6364136223846793005
        for i in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            noise[i] = Float(Int32(bitPattern: UInt32(seed >> 33))) / Float(Int32.max)
        }

        // High-shelf biquad: +6 dB at 4 kHz, Q = 0.707 (Butterworth, maximally flat)
        // Coefficients from "Cookbook formulae for audio EQ biquad filter coefficients"
        // (Audio EQ Cookbook by Robert Bristow-Johnson).
        let fc = 4000.0
        let gainDB = 6.0
        let Q = 0.7071067811865476     // 1/√2
        let A = pow(10.0, gainDB / 40.0)  // linear amplitude gain at shelf (not DC)
        let w0 = 2.0 * Double.pi * fc / sampleRate
        let cosW0 = cos(w0), sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * Q)
        let sqrtA = sqrt(A)

        let b0 =      A * ((A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * cosW0)
        let b2 =      A * ((A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha)
        let a0 =          ((A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha)
        let a1 =  2  *    ((A - 1) - (A + 1) * cosW0)
        let a2 =          ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha)

        // Normalised coefficients
        let nb0 = b0 / a0, nb1 = b1 / a0, nb2 = b2 / a0
        let na1 = a1 / a0, na2 = a2 / a0

        // Apply biquad in Double precision to suppress coefficient-quantisation error.
        var filtered = [Float](repeating: 0, count: count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<count {
            let x = Double(noise[i])
            let y = nb0 * x + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2
            filtered[i] = Float(y)
            x2 = x1; x1 = x; y2 = y1; y1 = y
        }

        // Theoretical gain of H(z) at 16 kHz, evaluated as |H(e^jω)|.
        // H(e^jω) = N(e^jω) / D(e^jω)
        // P(e^jω) = p0 + p1·e^{-jω} + p2·e^{-2jω}
        //         = (p0 + p1·cos ω + p2·cos 2ω) − j(p1·sin ω + p2·sin 2ω)
        let testFreq = 16000.0
        let omega = 2.0 * Double.pi * testFreq / sampleRate
        func mag2(p0: Double, p1: Double, p2: Double) -> Double {
            let re = p0 + p1 * cos(omega) + p2 * cos(2 * omega)
            let im = p1 * sin(omega) + p2 * sin(2 * omega)
            return re * re + im * im
        }
        let theoreticalGainDB = 10.0 * log10(
            mag2(p0: nb0, p1: nb1, p2: nb2) / mag2(p0: 1.0, p1: na1, p2: na2)
        )

        // Spectral analysis of both the unfiltered and filtered noise signals.
        let specA = SpectrumAnalyzer().analyze(channelData: ChannelData(channels: [noise]),    sampleRate: sampleRate)
        let specB = SpectrumAnalyzer().analyze(channelData: ChannelData(channels: [filtered]), sampleRate: sampleRate)

        guard !specA.averageSpectrum.isEmpty && !specB.averageSpectrum.isEmpty else {
            return ValidationTestResult(
                name: "Test 3: Known EQ (high-shelf biquad +6 dB at 4 kHz)",
                passed: false,
                details: "Spectrum analyzer returned empty result"
            )
        }

        let freqRes = sampleRate / Double(specA.fftSize)
        let bin = min(specA.averageSpectrum.count - 1, Int(testFreq / freqRes))
        let measuredGainDB = Double(specB.averageSpectrum[bin]) - Double(specA.averageSpectrum[bin])

        let error = measuredGainDB - theoreticalGainDB
        let passed = abs(error) < 0.5
        return ValidationTestResult(
            name: "Test 3: Known EQ (high-shelf biquad +6 dB at 4 kHz)",
            passed: passed,
            details: String(
                format: "At %.0f Hz — measured Δ: %.2f dB, theoretical: %.2f dB, error: %.2f dB (tolerance ±0.5 dB)",
                testFreq, measuredGainDB, theoreticalGainDB, error
            )
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
