import Foundation
import Accelerate

struct LoudnessResult: Codable {
    let integratedLUFS: Double
    let momentaryMaxLUFS: Double
    let shortTermMaxLUFS: Double
    let loudnessRangeLU: Double
    let momentaryTimeSeries: [Double]
    let shortTermTimeSeries: [Double]
    let blockDurationMs: Double
}

struct LoudnessMeter {
    func measure(kWeightedData: ChannelData, sampleRate: Double) -> LoudnessResult {
        let channels = kWeightedData.channels
        let channelWeights = channels.map { _ in 1.0 } // G=1.0 for L, R, mono

        // Momentary: 400 ms blocks, 100 ms hop
        let momentaryBlockSize = Int(sampleRate * 0.4)
        let momentaryHop = Int(sampleRate * 0.1)
        let momentaryValues = computeBlockLoudness(
            channels: channels,
            weights: channelWeights,
            blockSize: momentaryBlockSize,
            hopSize: momentaryHop
        )

        // Short-term: 3 s blocks, 1 s hop
        let shortTermBlockSize = Int(sampleRate * 3.0)
        let shortTermHop = Int(sampleRate * 1.0)
        let shortTermValues = computeBlockLoudness(
            channels: channels,
            weights: channelWeights,
            blockSize: shortTermBlockSize,
            hopSize: shortTermHop
        )

        // Integrated loudness with gating
        let integratedLUFS = computeGatedIntegrated(momentaryValues: momentaryValues)

        // Momentary and short-term max
        let momentaryMax = momentaryValues.max() ?? -Double.infinity
        let shortTermMax = shortTermValues.max() ?? -Double.infinity

        // LRA
        let lra = computeLRA(shortTermValues: shortTermValues)

        return LoudnessResult(
            integratedLUFS: integratedLUFS,
            momentaryMaxLUFS: momentaryMax,
            shortTermMaxLUFS: shortTermMax,
            loudnessRangeLU: lra,
            momentaryTimeSeries: momentaryValues,
            shortTermTimeSeries: shortTermValues,
            blockDurationMs: 100.0
        )
    }

    private func computeBlockLoudness(
        channels: [[Float]],
        weights: [Double],
        blockSize: Int,
        hopSize: Int
    ) -> [Double] {
        guard let firstChannel = channels.first else { return [] }
        let totalSamples = firstChannel.count
        guard totalSamples >= blockSize else { return [] }

        var results: [Double] = []
        var offset = 0

        while offset + blockSize <= totalSamples {
            var z = 0.0
            for (chIdx, channel) in channels.enumerated() {
                var meanSquare: Float = 0
                channel.withUnsafeBufferPointer { buffer in
                    let ptr = buffer.baseAddress! + offset
                    vDSP_measqv(ptr, 1, &meanSquare, vDSP_Length(blockSize))
                }
                z += weights[chIdx] * Double(meanSquare)
            }

            let lufs: Double
            if z > 0 {
                lufs = -0.691 + 10.0 * log10(z)
            } else {
                lufs = -Double.infinity
            }
            results.append(lufs)
            offset += hopSize
        }

        return results
    }

    private func computeGatedIntegrated(momentaryValues: [Double]) -> Double {
        // Absolute gate: -70 LUFS
        let absoluteGate = -70.0
        let afterAbsolute = momentaryValues.filter { $0 > absoluteGate }

        guard !afterAbsolute.isEmpty else { return -Double.infinity }

        // Mean in linear domain
        let linearValues = afterAbsolute.map { pow(10.0, ($0 + 0.691) / 10.0) }
        let meanLinear = linearValues.reduce(0.0, +) / Double(linearValues.count)
        let meanLUFS = -0.691 + 10.0 * log10(meanLinear)

        // Relative gate: mean - 10 LU
        let relativeGate = meanLUFS - 10.0
        let afterRelative = momentaryValues.filter { $0 > absoluteGate && $0 > relativeGate }

        guard !afterRelative.isEmpty else { return -Double.infinity }

        let relLinear = afterRelative.map { pow(10.0, ($0 + 0.691) / 10.0) }
        let relMean = relLinear.reduce(0.0, +) / Double(relLinear.count)

        return -0.691 + 10.0 * log10(relMean)
    }

    private func computeLRA(shortTermValues: [Double]) -> Double {
        // Absolute gate at -70 LUFS
        let absoluteGate = -70.0
        let afterAbsolute = shortTermValues.filter { $0 > absoluteGate }

        guard afterAbsolute.count >= 2 else { return 0.0 }

        // Ungated mean for relative gate (using -20 LU for LRA)
        let linearValues = afterAbsolute.map { pow(10.0, ($0 + 0.691) / 10.0) }
        let meanLinear = linearValues.reduce(0.0, +) / Double(linearValues.count)
        let meanLUFS = -0.691 + 10.0 * log10(meanLinear)

        let relativeGate = meanLUFS - 20.0
        var afterRelative = afterAbsolute.filter { $0 > relativeGate }

        guard afterRelative.count >= 2 else { return 0.0 }

        afterRelative.sort()

        // 10th and 95th percentile
        let p10Index = Int(Double(afterRelative.count - 1) * 0.10)
        let p95Index = Int(Double(afterRelative.count - 1) * 0.95)

        let p10 = afterRelative[p10Index]
        let p95 = afterRelative[p95Index]

        return p95 - p10
    }
}
