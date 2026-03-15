import Foundation
import Accelerate

struct DynamicsResult: Codable {
    let plrDB: Double
    let crestFactorTimeSeries: [Double]
    let minimumCrestFactor: Double
    let averageCrestFactor: Double
    let rmsPerChannelDBFS: [Double]
    let rmsSummedDBFS: Double
    let blockDurationMs: Double
}

// DynamicsAnalyzer is a struct (value type) so it is automatically Sendable.
struct DynamicsAnalyzer {
    func analyze(
        channelData: ChannelData,
        loudness: LoudnessResult,
        truePeak: TruePeakResult,
        sampleRate: Double
    ) -> DynamicsResult {
        let plr = truePeak.maxTruePeakDBTP - loudness.integratedLUFS

        // Crest factor: compute on the mono sum of all active channels.
        // Using left-only was wrong for stereo — the right channel was silently ignored.
        // A mono sum represents overall programme loudness and gives the correct crest value
        // for multi-channel content without requiring per-channel min/max decisions.
        let monoSignal = monoSum(channelData.channels)

        let blockSize = Int(sampleRate * 3.0)
        let hopSize = Int(sampleRate * 1.0)
        var crestFactors: [Double] = []

        var offset = 0
        while offset + blockSize <= monoSignal.count {
            let block = Array(monoSignal[offset..<offset + blockSize])

            var maxVal: Float = 0
            vDSP_maxmgv(block, 1, &maxVal, vDSP_Length(blockSize))

            var rmsVal: Float = 0
            vDSP_rmsqv(block, 1, &rmsVal, vDSP_Length(blockSize))

            if rmsVal > 0 && maxVal > 0 {
                let peakDB = 20.0 * log10(Double(maxVal))
                let rmsDB = 20.0 * log10(Double(rmsVal))
                crestFactors.append(peakDB - rmsDB)
            } else {
                crestFactors.append(0.0)
            }

            offset += hopSize
        }

        let avgCrest = crestFactors.isEmpty ? 0.0 : crestFactors.reduce(0.0, +) / Double(crestFactors.count)
        let minCrest = crestFactors.min() ?? 0.0

        // Full-file RMS per channel
        var rmsPerChannel: [Double] = []
        for ch in channelData.channels {
            var rms: Float = 0
            vDSP_rmsqv(ch, 1, &rms, vDSP_Length(ch.count))
            if rms > 0 {
                rmsPerChannel.append(20.0 * log10(Double(rms)))
            } else {
                rmsPerChannel.append(-Double.infinity)
            }
        }

        // Summed RMS (combine channels)
        let linearSum = rmsPerChannel.reduce(0.0) { sum, dbVal in
            if dbVal.isFinite {
                return sum + pow(10.0, dbVal / 10.0)
            }
            return sum
        }
        let rmsSummedDBFS = linearSum > 0 ? 10.0 * log10(linearSum / Double(channelData.channels.count)) : -Double.infinity

        return DynamicsResult(
            plrDB: plr,
            crestFactorTimeSeries: crestFactors,
            minimumCrestFactor: minCrest,
            averageCrestFactor: avgCrest,
            rmsPerChannelDBFS: rmsPerChannel,
            rmsSummedDBFS: rmsSummedDBFS,
            blockDurationMs: 1000.0
        )
    }

    // Average all channels into a single mono signal.
    private func monoSum(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }

        let count = channels.map(\.count).min()!
        var result = [Float](repeating: 0, count: count)
        for ch in channels {
            vDSP_vadd(result, 1, ch, 1, &result, 1, vDSP_Length(count))
        }
        var scale = Float(1.0) / Float(channels.count)
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(count))
        return result
    }
}
