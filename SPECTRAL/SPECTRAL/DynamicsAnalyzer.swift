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

class DynamicsAnalyzer {
    func analyze(
        channelData: ChannelData,
        loudness: LoudnessResult,
        truePeak: TruePeakResult,
        sampleRate: Double
    ) -> DynamicsResult {
        // PLR: |truePeakDBTP| - |integratedLUFS|
        // More precisely: truePeakDBTP - integratedLUFS (both are typically negative)
        let plr = truePeak.maxTruePeakDBTP - loudness.integratedLUFS

        // Crest factor per 3s block, 1s hop (uses sample peak, not oversampled)
        let blockSize = Int(sampleRate * 3.0)
        let hopSize = Int(sampleRate * 1.0)
        var crestFactors: [Double] = []

        let channel = channelData.left
        var offset = 0
        while offset + blockSize <= channel.count {
            let block = Array(channel[offset..<offset + blockSize])

            // Sample peak
            var maxVal: Float = 0
            vDSP_maxmgv(block, 1, &maxVal, vDSP_Length(blockSize))

            // RMS
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
}
