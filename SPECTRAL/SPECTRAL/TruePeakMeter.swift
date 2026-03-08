import Foundation
import Accelerate

enum OversamplingRatio: Int, CaseIterable, Codable {
    case x4 = 4
    case x8 = 8
    case x16 = 16
    case x32 = 32
}

struct TruePeakResult: Codable {
    let maxTruePeakDBTP: Double
    let perChannelTruePeakDBTP: [Double]
    let peakSampleIndex: Int64
    let peakTimeSeconds: Double
    let oversamplingRatio: Int
}

// TruePeakMeter is a struct so it is automatically Sendable — safe to capture in detached Tasks.
struct TruePeakMeter {
    // Kaiser window β = 8.0 → ~81 dB stopband attenuation.
    // BS.1770-5 requires ≥ 80 dB. A Hann window achieves only ~44 dB and is not compliant.
    // β = 8.0 satisfies the Parks-McClellan approximation: A_dB ≈ 2.285*(N-1)*Δω + 7.95 ≥ 80 dB.
    private static let kaiserBeta: Double = 8.0
    // 12 taps per phase balances stopband depth against computation. At 8×, total prototype
    // length = 96 taps; transition band ≈ 0.9*(fs/2 / factor) = 2.7 kHz at 48 kHz input.
    private static let tapsPerPhase: Int = 12

    func measure(channelData: ChannelData, sampleRate: Double, ratio: OversamplingRatio) -> TruePeakResult {
        let factor = ratio.rawValue
        let filter = designPolyphaseFilter(factor: factor)

        var globalMax: Float = 0.0
        var globalPeakIndex: Int64 = 0
        var perChannelPeaks: [Float] = []

        for channel in channelData.channels {
            let (chMax, chIdx) = measureChannel(samples: channel, filter: filter, factor: factor)
            perChannelPeaks.append(chMax)
            if chMax > globalMax {
                globalMax = chMax
                globalPeakIndex = Int64(chIdx)
            }
        }

        let peakDBTP = globalMax > 0 ? 20.0 * log10(Double(globalMax)) : -Double.infinity
        let perChannelDBTP = perChannelPeaks.map { p in
            p > 0 ? 20.0 * log10(Double(p)) : -Double.infinity
        }

        return TruePeakResult(
            maxTruePeakDBTP: peakDBTP,
            perChannelTruePeakDBTP: perChannelDBTP,
            peakSampleIndex: globalPeakIndex,
            peakTimeSeconds: Double(globalPeakIndex) / sampleRate,
            oversamplingRatio: factor
        )
    }

    // MARK: - Per-channel measurement using vDSP_dotpr
    //
    // Replaces the triple-nested scalar loop (O(samples × phases × taps)) with
    // vDSP_dotpr for the inner tap accumulation. For a 4-minute stereo file at
    // 48 kHz × 8 phases × 12 taps the scalar loop required ~2.2 billion MACs;
    // vDSP_dotpr executes those MACs in SIMD, reducing wall-time from minutes to seconds.
    //
    // Zero-padding the input by halfTaps on each end lets every position use a full
    // contiguous filter window, eliminating the bounds-check branch inside the loop.

    private func measureChannel(
        samples: [Float],
        filter: [[Float]],
        factor: Int
    ) -> (Float, Int) {
        let tapsPerPhase = TruePeakMeter.tapsPerPhase
        let halfTaps = tapsPerPhase / 2

        // Pad so every sample index has a full tapsPerPhase window to the left.
        let padded = [Float](repeating: 0, count: halfTaps) + samples + [Float](repeating: 0, count: halfTaps)
        let sampleCount = samples.count

        var maxAbsValue: Float = 0.0
        var maxIndex = 0

        padded.withUnsafeBufferPointer { paddedBuf in
            let base = paddedBuf.baseAddress!
            for i in 0..<sampleCount {
                // base + i spans [samples[i - halfTaps] … samples[i + halfTaps - 1]]
                // (the leading halfTaps zeros shift the window origin correctly).
                let inputPtr = base + i
                for phase in 0..<factor {
                    var sum: Float = 0.0
                    filter[phase].withUnsafeBufferPointer { fb in
                        vDSP_dotpr(inputPtr, 1, fb.baseAddress!, 1, &sum, vDSP_Length(tapsPerPhase))
                    }
                    let absVal = abs(sum)
                    if absVal > maxAbsValue {
                        maxAbsValue = absVal
                        maxIndex = i
                    }
                }
            }
        }

        return (maxAbsValue, maxIndex)
    }

    // MARK: - Kaiser-windowed polyphase FIR prototype

    private func designPolyphaseFilter(factor: Int) -> [[Float]] {
        let tapsPerPhase = TruePeakMeter.tapsPerPhase
        let totalTaps = tapsPerPhase * factor
        let beta = TruePeakMeter.kaiserBeta
        let i0Beta = modifiedBesselI0(beta)
        let center = Double(totalTaps - 1) / 2.0

        var prototype = [Float](repeating: 0, count: totalTaps)
        for n in 0..<totalTaps {
            let x = Double(n) - center

            // Windowed-sinc: cutoff at π/factor (Nyquist of original rate).
            let sinc: Double
            if abs(x) < 1e-10 {
                sinc = 1.0
            } else {
                let arg = Double.pi * x / Double(factor)
                sinc = sin(arg) / arg
            }

            // Kaiser window: w(n) = I0(β√(1 − ((2n/(N−1)) − 1)²)) / I0(β)
            let t = 2.0 * Double(n) / Double(totalTaps - 1) - 1.0   // ∈ [−1, 1]
            let windowArg = beta * sqrt(max(0.0, 1.0 - t * t))
            let window = modifiedBesselI0(windowArg) / i0Beta

            // Scale by factor so interpolated amplitude matches original (unity gain).
            prototype[n] = Float(sinc * window * Double(factor))
        }

        // Decompose prototype into polyphase branches.
        // Branch p picks every factor-th sample starting at offset p.
        var polyphase = [[Float]](
            repeating: [Float](repeating: 0, count: tapsPerPhase),
            count: factor
        )
        for phase in 0..<factor {
            for tap in 0..<tapsPerPhase {
                let protoIdx = tap * factor + phase
                if protoIdx < totalTaps {
                    polyphase[phase][tap] = prototype[protoIdx]
                }
            }
        }
        return polyphase
    }

    // MARK: - Zeroth-order modified Bessel function I0
    // Series expansion: I0(x) = Σ_{k=0}^∞ ((x/2)^k / k!)²
    // Converges to Double precision within ≤ 25 terms for β ≤ 10.
    private func modifiedBesselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let halfX = x / 2.0
        for k in 1...35 {
            let t = halfX / Double(k)
            term *= t * t
            sum += term
            if term < sum * 1e-16 { break }
        }
        return sum
    }
}
