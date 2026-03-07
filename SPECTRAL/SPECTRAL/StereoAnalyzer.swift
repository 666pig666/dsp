import Foundation
import Accelerate

struct StereoResult: Codable {
    let correlationTimeSeries: [Double]
    let averageCorrelation: Double
    let minimumCorrelation: Double
    let midSideRatioDB: Double
    let blockDurationMs: Double
}

class StereoAnalyzer {
    func analyze(left: [Float], right: [Float], sampleRate: Double) -> StereoResult? {
        guard !left.isEmpty && !right.isEmpty else { return nil }

        let blockSize = Int(sampleRate * 0.4)  // 400 ms
        let hopSize = Int(sampleRate * 0.1)    // 100 ms
        let totalSamples = min(left.count, right.count)

        guard totalSamples >= blockSize else { return nil }

        var correlationSeries: [Double] = []
        var offset = 0

        while offset + blockSize <= totalSamples {
            let lBlock = Array(left[offset..<offset + blockSize])
            let rBlock = Array(right[offset..<offset + blockSize])

            // r = sum(L*R) / sqrt(sum(L^2) * sum(R^2))
            var dotProduct: Float = 0
            vDSP_dotpr(lBlock, 1, rBlock, 1, &dotProduct, vDSP_Length(blockSize))

            var sumSqL: Float = 0
            var sumSqR: Float = 0
            vDSP_svesq(lBlock, 1, &sumSqL, vDSP_Length(blockSize))
            vDSP_svesq(rBlock, 1, &sumSqR, vDSP_Length(blockSize))

            let denominator = sqrt(Double(sumSqL) * Double(sumSqR))
            let correlation: Double
            if denominator > 0 {
                correlation = Double(dotProduct) / denominator
            } else {
                correlation = 0.0
            }

            correlationSeries.append(correlation)
            offset += hopSize
        }

        let avgCorrelation: Double
        if correlationSeries.isEmpty {
            avgCorrelation = 0.0
        } else {
            avgCorrelation = correlationSeries.reduce(0.0, +) / Double(correlationSeries.count)
        }
        let minCorrelation = correlationSeries.min() ?? 0.0

        // M/S energy ratio
        let count = min(left.count, right.count)
        var mid = [Float](repeating: 0, count: count)
        var side = [Float](repeating: 0, count: count)

        vDSP_vadd(left, 1, right, 1, &mid, 1, vDSP_Length(count))
        var half: Float = 0.5
        vDSP_vsmul(mid, 1, &half, &mid, 1, vDSP_Length(count))

        vDSP_vsub(right, 1, left, 1, &side, 1, vDSP_Length(count))
        vDSP_vsmul(side, 1, &half, &side, 1, vDSP_Length(count))

        var rmsM: Float = 0
        var rmsS: Float = 0
        vDSP_rmsqv(mid, 1, &rmsM, vDSP_Length(count))
        vDSP_rmsqv(side, 1, &rmsS, vDSP_Length(count))

        let msRatioDB: Double
        if rmsS > 0 {
            msRatioDB = 20.0 * log10(Double(rmsM) / Double(rmsS))
        } else {
            msRatioDB = Double.infinity
        }

        return StereoResult(
            correlationTimeSeries: correlationSeries,
            averageCorrelation: avgCorrelation,
            minimumCorrelation: minCorrelation,
            midSideRatioDB: msRatioDB,
            blockDurationMs: 100.0
        )
    }
}
