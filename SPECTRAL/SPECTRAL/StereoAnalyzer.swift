import Foundation
import Accelerate

/// A single sampled stereo position for the Lissajous/goniometer display.
struct StereographPoint: Codable {
    /// Mid = (rmsL + rmsR) / 2
    let m: Float
    /// Side = (rmsL - rmsR) / 2  (positive = left-heavy, negative = right-heavy)
    let s: Float
}

struct StereoResult: Codable {
    let correlationTimeSeries: [Double]
    let averageCorrelation: Double
    let minimumCorrelation: Double
    let midSideRatioDB: Double
    let blockDurationMs: Double
    /// 10,000 evenly-spaced RMS-based M/S samples for StereographView rendering.
    let stereographPoints: [StereographPoint]
}

struct StereoAnalyzer {
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

        // Stereograph: 10,000 evenly-spaced RMS-based M/S samples
        let targetPoints = 10_000
        let windowSize = 64
        let totalSamples = min(left.count, right.count)
        var stereographPoints = [StereographPoint]()
        stereographPoints.reserveCapacity(targetPoints)
        for i in 0..<targetPoints {
            let centerIdx = Int(Double(i) * Double(totalSamples) / Double(targetPoints))
            let startIdx = max(0, min(centerIdx, totalSamples - windowSize))
            let endIdx = startIdx + windowSize
            let lWindow = Array(left[startIdx..<endIdx])
            let rWindow = Array(right[startIdx..<endIdx])
            var rmsL: Float = 0
            var rmsR: Float = 0
            vDSP_rmsqv(lWindow, 1, &rmsL, vDSP_Length(windowSize))
            vDSP_rmsqv(rWindow, 1, &rmsR, vDSP_Length(windowSize))
            stereographPoints.append(StereographPoint(
                m: (rmsL + rmsR) * 0.5,
                s: (rmsL - rmsR) * 0.5
            ))
        }

        return StereoResult(
            correlationTimeSeries: correlationSeries,
            averageCorrelation: avgCorrelation,
            minimumCorrelation: minCorrelation,
            midSideRatioDB: msRatioDB,
            blockDurationMs: 100.0,
            stereographPoints: stereographPoints
        )
    }
}
