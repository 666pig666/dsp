import Foundation
import CryptoKit

@MainActor
class AnalysisPipeline: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var currentStage: String = ""

    private let decoder = AudioDecoder()
    private let kWeightingFilterFactory: (Double) -> KWeightingFilter = { KWeightingFilter(sampleRate: $0) }
    private let loudnessMeter = LoudnessMeter()
    private let truePeakMeter = TruePeakMeter()
    private let spectrumAnalyzer = SpectrumAnalyzer()
    private let stereoAnalyzer = StereoAnalyzer()
    private let dynamicsAnalyzer = DynamicsAnalyzer()
    private let cache = AnalysisCache()

    func analyze(
        url: URL,
        channelMode: ChannelMode,
        oversamplingRatio: OversamplingRatio = .x8
    ) async throws -> AnalysisResult {
        // Check cache
        if let cached = cache.load(url: url, channelMode: channelMode, oversamplingRatio: oversamplingRatio) {
            return cached
        }

        // Stage 1: Decode
        currentStage = "Decoding audio..."
        progress = 0.05
        let decoded = try await decoder.decode(url: url)

        // Stage 2: Derive channels
        currentStage = "Deriving channels..."
        progress = 0.15
        let channelData = ChannelDeriver.derive(from: decoded, mode: channelMode)

        // Stage 3: K-weight
        currentStage = "Applying K-weighting..."
        progress = 0.25
        let filter = kWeightingFilterFactory(decoded.sampleRate)
        let kWeighted = await Task.detached {
            filter.processChannelData(channelData)
        }.value

        // Stage 4: Loudness
        currentStage = "Measuring loudness..."
        progress = 0.40
        let loudness = await Task.detached {
            self.loudnessMeter.measure(kWeightedData: kWeighted, sampleRate: decoded.sampleRate)
        }.value

        // Stage 5: True peak
        currentStage = "Measuring true peak..."
        progress = 0.55
        let truePeakResult = await Task.detached {
            self.truePeakMeter.measure(channelData: channelData, sampleRate: decoded.sampleRate, ratio: oversamplingRatio)
        }.value

        // Stage 6: Spectrum
        currentStage = "Analyzing spectrum..."
        progress = 0.70
        let spectrum = await Task.detached {
            self.spectrumAnalyzer.analyze(channelData: channelData, sampleRate: decoded.sampleRate)
        }.value

        // Stage 7: Stereo analysis
        currentStage = "Analyzing stereo field..."
        progress = 0.80
        var stereoResult: StereoResult?
        if channelMode == .stereo, let right = decoded.right {
            stereoResult = await Task.detached {
                self.stereoAnalyzer.analyze(left: decoded.left, right: right, sampleRate: decoded.sampleRate)
            }.value
        }

        // Stage 8: Dynamics
        currentStage = "Computing dynamics..."
        progress = 0.90
        let dynamics = await Task.detached {
            self.dynamicsAnalyzer.analyze(
                channelData: channelData,
                loudness: loudness,
                truePeak: truePeakResult,
                sampleRate: decoded.sampleRate
            )
        }.value

        // Assemble result
        currentStage = "Complete"
        progress = 1.0

        let result = AnalysisResult(
            id: UUID(),
            metadata: decoded.metadata,
            channelMode: channelMode,
            loudness: loudness,
            truePeak: truePeakResult,
            spectrum: spectrum,
            stereo: stereoResult,
            dynamics: dynamics,
            analysisDate: Date(),
            oversamplingRatio: oversamplingRatio.rawValue
        )

        cache.save(result: result, url: url, channelMode: channelMode, oversamplingRatio: oversamplingRatio)

        return result
    }
}

class AnalysisCache {
    private let fileManager = FileManager.default

    private var cacheDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = docs.appendingPathComponent("AnalysisCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }

    func cacheKey(url: URL, channelMode: ChannelMode, oversamplingRatio: OversamplingRatio) -> String {
        let fileName = url.lastPathComponent
        let fileSize: Int64
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        let input = "\(fileName)|\(fileSize)|\(channelMode.rawValue)|\(oversamplingRatio.rawValue)"
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    func load(url: URL, channelMode: ChannelMode, oversamplingRatio: OversamplingRatio) -> AnalysisResult? {
        let key = cacheKey(url: url, channelMode: channelMode, oversamplingRatio: oversamplingRatio)
        let filePath = cacheDirectory.appendingPathComponent("\(key).json")

        guard let data = try? Data(contentsOf: filePath) else { return nil }

        do {
            return try JSONDecoder().decode(AnalysisResult.self, from: data)
        } catch {
            return nil
        }
    }

    func save(result: AnalysisResult, url: URL, channelMode: ChannelMode, oversamplingRatio: OversamplingRatio) {
        let key = cacheKey(url: url, channelMode: channelMode, oversamplingRatio: oversamplingRatio)
        let filePath = cacheDirectory.appendingPathComponent("\(key).json")

        do {
            let data = try JSONEncoder().encode(result)
            try data.write(to: filePath)
        } catch {
            // Cache write failure is non-fatal
        }
    }

    func prune() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return }

        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600) // 7 days
        for file in files {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               created < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
