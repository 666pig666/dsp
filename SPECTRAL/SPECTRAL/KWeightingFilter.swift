import Foundation
import Accelerate

class KWeightingFilter {
    private var highShelfState: BiquadState
    private var rlbHighPassState: BiquadState

    private let highShelfCoeffs: BiquadCoefficients
    private let rlbHighPassCoeffs: BiquadCoefficients

    init(sampleRate: Double) {
        if sampleRate == 48000.0 {
            // BS.1770-5 hardcoded 48 kHz coefficients
            highShelfCoeffs = BiquadCoefficients(
                b0: 1.53512485958697,
                b1: -2.69169618940638,
                b2: 1.19839281085285,
                a1: -1.69065929318241,
                a2: 0.73248077421585
            )
            rlbHighPassCoeffs = BiquadCoefficients(
                b0: 1.0,
                b1: -2.0,
                b2: 1.0,
                a1: -1.99004745483398,
                a2: 0.99007225036621
            )
        } else {
            // Derive coefficients for arbitrary sample rates using bilinear transform
            highShelfCoeffs = KWeightingFilter.deriveHighShelfCoefficients(sampleRate: sampleRate)
            rlbHighPassCoeffs = KWeightingFilter.deriveRLBHighPassCoefficients(sampleRate: sampleRate)
        }

        highShelfState = BiquadState()
        rlbHighPassState = BiquadState()
    }

    func reset() {
        highShelfState = BiquadState()
        rlbHighPassState = BiquadState()
    }

    func process(samples: [Float]) -> [Float] {
        // Double-precision biquad processing for correctness
        var output = [Float](repeating: 0, count: samples.count)

        // Stage 1: High-shelf filter
        for i in 0..<samples.count {
            let x = Double(samples[i])
            let y = highShelfCoeffs.b0 * x
                + highShelfCoeffs.b1 * highShelfState.x1
                + highShelfCoeffs.b2 * highShelfState.x2
                - highShelfCoeffs.a1 * highShelfState.y1
                - highShelfCoeffs.a2 * highShelfState.y2

            highShelfState.x2 = highShelfState.x1
            highShelfState.x1 = x
            highShelfState.y2 = highShelfState.y1
            highShelfState.y1 = y

            output[i] = Float(y)
        }

        // Stage 2: RLB high-pass filter
        var stage1Output = output
        for i in 0..<stage1Output.count {
            let x = Double(stage1Output[i])
            let y = rlbHighPassCoeffs.b0 * x
                + rlbHighPassCoeffs.b1 * rlbHighPassState.x1
                + rlbHighPassCoeffs.b2 * rlbHighPassState.x2
                - rlbHighPassCoeffs.a1 * rlbHighPassState.y1
                - rlbHighPassCoeffs.a2 * rlbHighPassState.y2

            rlbHighPassState.x2 = rlbHighPassState.x1
            rlbHighPassState.x1 = x
            rlbHighPassState.y2 = rlbHighPassState.y1
            rlbHighPassState.y1 = y

            output[i] = Float(y)
        }

        return output
    }

    func processChannelData(_ channelData: ChannelData) -> ChannelData {
        var processedChannels: [[Float]] = []
        for channel in channelData.channels {
            reset()
            processedChannels.append(process(samples: channel))
        }
        return ChannelData(channels: processedChannels)
    }

    // MARK: - Coefficient derivation via bilinear transform

    private static func deriveHighShelfCoefficients(sampleRate: Double) -> BiquadCoefficients {
        // High-shelf: fc ~ 1681.974 Hz, gain ~ +3.9997 dB, Q ~ 0.7084
        let fc = 1681.974450955533
        let gainDB = 3.999843853973347
        let Q = 0.7083955550885168

        let A = pow(10.0, gainDB / 40.0) // sqrt of linear gain
        let w0 = 2.0 * Double.pi * fc / sampleRate
        let sinW0 = sin(w0)
        let cosW0 = cos(w0)
        let alpha = sinW0 / (2.0 * Q)

        let b0 = A * ((A + 1) + (A - 1) * cosW0 + 2.0 * sqrt(A) * alpha)
        let b1 = -2.0 * A * ((A - 1) + (A + 1) * cosW0)
        let b2 = A * ((A + 1) + (A - 1) * cosW0 - 2.0 * sqrt(A) * alpha)
        let a0 = (A + 1) - (A - 1) * cosW0 + 2.0 * sqrt(A) * alpha
        let a1 = 2.0 * ((A - 1) - (A + 1) * cosW0)
        let a2 = (A + 1) - (A - 1) * cosW0 - 2.0 * sqrt(A) * alpha

        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }

    private static func deriveRLBHighPassCoefficients(sampleRate: Double) -> BiquadCoefficients {
        // RLB high-pass: fc ~ 38.13 Hz, Q ~ 0.5003
        let fc = 38.13547087602444
        let Q = 0.5003270373238773

        let w0 = 2.0 * Double.pi * fc / sampleRate
        let sinW0 = sin(w0)
        let cosW0 = cos(w0)
        let alpha = sinW0 / (2.0 * Q)

        let b0 = (1.0 + cosW0) / 2.0
        let b1 = -(1.0 + cosW0)
        let b2 = (1.0 + cosW0) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha

        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}

struct BiquadCoefficients {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double
}

struct BiquadState {
    var x1: Double = 0.0
    var x2: Double = 0.0
    var y1: Double = 0.0
    var y2: Double = 0.0
}
