import Foundation
import Accelerate

struct BandEnergy: Codable {
    let centerFrequency: Double
    let lowerEdge: Double
    let upperEdge: Double
    let energyDB: Double
}

struct SpectralBalance: Codable {
    let subDB: Double      // <= 60 Hz
    let lowDB: Double      // 60-250 Hz
    let lowMidDB: Double   // 250-1000 Hz
    let highMidDB: Double  // 1-6 kHz
    let highDB: Double     // 6-20 kHz
}

struct SpectrumResult: Codable {
    let averageSpectrum: [Float]
    let peakHoldSpectrum: [Float]
    let frequencyAxis: [Float]
    let fftSize: Int
    let octaveBands: [BandEnergy]
    let thirdOctaveBands: [BandEnergy]
    let spectralBalance: SpectralBalance
}

class SpectrumAnalyzer {
    func analyze(channelData: ChannelData, sampleRate: Double, fftSize: Int = 8192) -> SpectrumResult {
        let channel = channelData.left
        let halfFFT = fftSize / 2
        let log2n = vDSP_Length(log2(Double(fftSize)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return emptyResult(fftSize: fftSize, sampleRate: sampleRate)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Create Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let hopSize = fftSize / 4 // 75% overlap
        var sumSquaredMag = [Double](repeating: 0, count: halfFFT)
        var peakMag = [Float](repeating: 0, count: halfFFT)
        var blockCount = 0

        var offset = 0
        while offset + fftSize <= channel.count {
            // Window the block
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(Array(channel[offset..<offset + fftSize]), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            // FFT
            var realPart = [Float](repeating: 0, count: halfFFT)
            var imagPart = [Float](repeating: 0, count: halfFFT)
            windowed.withUnsafeBufferPointer { bufferPtr in
                realPart.withUnsafeMutableBufferPointer { realBuf in
                    imagPart.withUnsafeMutableBufferPointer { imagBuf in
                        var splitComplex = DSPSplitComplex(
                            realp: realBuf.baseAddress!,
                            imagp: imagBuf.baseAddress!
                        )
                        bufferPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfFFT))
                        }
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                    }
                }
            }

            // Compute magnitude
            var magnitude = [Float](repeating: 0, count: halfFFT)
            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(
                        realp: realBuf.baseAddress!,
                        imagp: imagBuf.baseAddress!
                    )
                    vDSP_zvabs(&splitComplex, 1, &magnitude, 1, vDSP_Length(halfFFT))
                }
            }

            // Normalize
            var scale = Float(2.0) / Float(fftSize)
            vDSP_vsmul(magnitude, 1, &scale, &magnitude, 1, vDSP_Length(halfFFT))

            // Accumulate for RMS average
            for i in 0..<halfFFT {
                sumSquaredMag[i] += Double(magnitude[i]) * Double(magnitude[i])
            }

            // Peak hold
            for i in 0..<halfFFT {
                if magnitude[i] > peakMag[i] {
                    peakMag[i] = magnitude[i]
                }
            }

            blockCount += 1
            offset += hopSize
        }

        // Average spectrum (RMS)
        var avgSpectrum = [Float](repeating: -120, count: halfFFT)
        if blockCount > 0 {
            for i in 0..<halfFFT {
                let rms = sqrt(sumSquaredMag[i] / Double(blockCount))
                if rms > 0 {
                    avgSpectrum[i] = Float(20.0 * log10(rms))
                }
            }
        }

        // Peak hold to dB
        var peakHoldSpectrum = [Float](repeating: -120, count: halfFFT)
        for i in 0..<halfFFT {
            if peakMag[i] > 0 {
                peakHoldSpectrum[i] = 20.0 * log10(peakMag[i])
            }
        }

        // Frequency axis
        let freqResolution = Float(sampleRate) / Float(fftSize)
        var frequencyAxis = [Float](repeating: 0, count: halfFFT)
        for i in 0..<halfFFT {
            frequencyAxis[i] = Float(i) * freqResolution
        }

        // Octave bands
        let octaveBands = computeOctaveBands(
            avgSpectrum: avgSpectrum,
            freqResolution: Double(freqResolution),
            n: 1
        )
        let thirdOctaveBands = computeOctaveBands(
            avgSpectrum: avgSpectrum,
            freqResolution: Double(freqResolution),
            n: 3
        )

        let spectralBalance = computeSpectralBalance(
            avgSpectrum: avgSpectrum,
            freqResolution: Double(freqResolution)
        )

        return SpectrumResult(
            averageSpectrum: avgSpectrum,
            peakHoldSpectrum: peakHoldSpectrum,
            frequencyAxis: frequencyAxis,
            fftSize: fftSize,
            octaveBands: octaveBands,
            thirdOctaveBands: thirdOctaveBands,
            spectralBalance: spectralBalance
        )
    }

    private func computeOctaveBands(
        avgSpectrum: [Float],
        freqResolution: Double,
        n: Int
    ) -> [BandEnergy] {
        let centerFrequencies: [Double]
        if n == 1 {
            centerFrequencies = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        } else {
            var freqs: [Double] = []
            var fc = 20.0
            while fc <= 20000 {
                freqs.append(fc)
                fc *= pow(2.0, 1.0 / Double(n))
            }
            centerFrequencies = freqs
        }

        return centerFrequencies.map { fc in
            let factor = pow(2.0, 1.0 / (2.0 * Double(n)))
            let lower = fc / factor
            let upper = fc * factor

            let lowerBin = max(1, Int(lower / freqResolution))
            let upperBin = min(avgSpectrum.count - 1, Int(upper / freqResolution))

            var energy = 0.0
            if upperBin >= lowerBin {
                for bin in lowerBin...upperBin {
                    let linearMag = pow(10.0, Double(avgSpectrum[bin]) / 20.0)
                    energy += linearMag * linearMag
                }
            }

            let energyDB = energy > 0 ? 10.0 * log10(energy) : -120.0

            return BandEnergy(
                centerFrequency: fc,
                lowerEdge: lower,
                upperEdge: upper,
                energyDB: energyDB
            )
        }
    }

    private func computeSpectralBalance(
        avgSpectrum: [Float],
        freqResolution: Double
    ) -> SpectralBalance {
        let ranges: [(String, Double, Double)] = [
            ("sub", 0, 60),
            ("low", 60, 250),
            ("lowMid", 250, 1000),
            ("highMid", 1000, 6000),
            ("high", 6000, 20000)
        ]

        var totalEnergy = 0.0
        var bandEnergies: [Double] = []

        for (_, lower, upper) in ranges {
            let lowerBin = max(1, Int(lower / freqResolution))
            let upperBin = min(avgSpectrum.count - 1, Int(upper / freqResolution))
            var energy = 0.0
            if upperBin >= lowerBin {
                for bin in lowerBin...upperBin {
                    let linearMag = pow(10.0, Double(avgSpectrum[bin]) / 20.0)
                    energy += linearMag * linearMag
                }
            }
            bandEnergies.append(energy)
            totalEnergy += energy
        }

        let toRelDB = { (energy: Double) -> Double in
            guard totalEnergy > 0 && energy > 0 else { return -120.0 }
            return 10.0 * log10(energy / totalEnergy)
        }

        return SpectralBalance(
            subDB: toRelDB(bandEnergies[0]),
            lowDB: toRelDB(bandEnergies[1]),
            lowMidDB: toRelDB(bandEnergies[2]),
            highMidDB: toRelDB(bandEnergies[3]),
            highDB: toRelDB(bandEnergies[4])
        )
    }

    private func emptyResult(fftSize: Int, sampleRate: Double) -> SpectrumResult {
        SpectrumResult(
            averageSpectrum: [],
            peakHoldSpectrum: [],
            frequencyAxis: [],
            fftSize: fftSize,
            octaveBands: [],
            thirdOctaveBands: [],
            spectralBalance: SpectralBalance(
                subDB: -120, lowDB: -120, lowMidDB: -120,
                highMidDB: -120, highDB: -120
            )
        )
    }
}
