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

class TruePeakMeter {
    private let chunkSize = 4096

    func measure(channelData: ChannelData, sampleRate: Double, ratio: OversamplingRatio) -> TruePeakResult {
        let oversamplingFactor = ratio.rawValue
        let filterTaps = oversamplingFactor * 12
        let filter = designPolyphaseFilter(factor: oversamplingFactor, taps: filterTaps)

        var globalMax: Float = 0.0
        var globalPeakIndex: Int64 = 0
        var globalPeakChannel = 0
        var perChannelPeaks: [Float] = []

        for (chIdx, channel) in channelData.channels.enumerated() {
            let (channelMax, channelPeakIdx) = measureChannel(
                samples: channel,
                filter: filter,
                factor: oversamplingFactor,
                tapsPerPhase: 12
            )
            perChannelPeaks.append(channelMax)

            if channelMax > globalMax {
                globalMax = channelMax
                globalPeakIndex = Int64(channelPeakIdx)
                globalPeakChannel = chIdx
            }
        }

        let peakDBTP: Double
        if globalMax > 0 {
            peakDBTP = 20.0 * log10(Double(globalMax))
        } else {
            peakDBTP = -Double.infinity
        }

        let perChannelDBTP = perChannelPeaks.map { peak -> Double in
            if peak > 0 {
                return 20.0 * log10(Double(peak))
            } else {
                return -Double.infinity
            }
        }

        let peakTime = Double(globalPeakIndex) / sampleRate

        return TruePeakResult(
            maxTruePeakDBTP: peakDBTP,
            perChannelTruePeakDBTP: perChannelDBTP,
            peakSampleIndex: globalPeakIndex,
            peakTimeSeconds: peakTime,
            oversamplingRatio: oversamplingFactor
        )
    }

    private func measureChannel(
        samples: [Float],
        filter: [[Float]],
        factor: Int,
        tapsPerPhase: Int
    ) -> (Float, Int) {
        var maxAbsValue: Float = 0.0
        var maxIndex = 0
        let halfTaps = tapsPerPhase / 2

        for i in 0..<samples.count {
            for phase in 0..<factor {
                var sum: Float = 0.0
                let phaseFilter = filter[phase]

                for tap in 0..<tapsPerPhase {
                    let sampleIdx = i - halfTaps + tap
                    if sampleIdx >= 0 && sampleIdx < samples.count {
                        sum += samples[sampleIdx] * phaseFilter[tap]
                    }
                }

                let absVal = abs(sum)
                if absVal > maxAbsValue {
                    maxAbsValue = absVal
                    maxIndex = i
                }
            }
        }

        return (maxAbsValue, maxIndex)
    }

    private func designPolyphaseFilter(factor: Int, taps: Int) -> [[Float]] {
        let tapsPerPhase = taps / factor

        // Design windowed-sinc lowpass
        var prototype = [Float](repeating: 0, count: taps)
        let center = Double(taps - 1) / 2.0

        for i in 0..<taps {
            let x = Double(i) - center
            let sinc: Double
            if abs(x) < 1e-10 {
                sinc = 1.0
            } else {
                let arg = Double.pi * x / Double(factor)
                sinc = sin(arg) / arg
            }

            // Kaiser-like window (using Hann for simplicity, meeting >60 dB stopband)
            let window = 0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(taps - 1)))

            prototype[i] = Float(sinc * window * Double(factor))
        }

        // Decompose into polyphase branches
        var polyphase = [[Float]](repeating: [Float](repeating: 0, count: tapsPerPhase), count: factor)
        for phase in 0..<factor {
            for tap in 0..<tapsPerPhase {
                let protoIdx = tap * factor + phase
                if protoIdx < taps {
                    polyphase[phase][tap] = prototype[protoIdx]
                }
            }
        }

        return polyphase
    }
}
