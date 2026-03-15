import Foundation
import CryptoKit

// AnalysisPipeline keeps @MainActor for @Published properties.
// All DSP runs in Task.detached so the main thread is never blocked.
// Each analyzer is a struct (value type, automatically Sendable) so it can be
// captured by value in detached closures without Sendable violations in Swift 6.
// KWeightingFilter is final + @unchecked Sendable (created fresh per call, single-task use).
@MainActor
class AnalysisPipeline: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var currentStage: String = ""

    private let decoder = AudioDecoder()
    private let cache = AnalysisCache()

    func pruneCache() {
        cache.prune()
    }

    func analyze(
        url: URL,
        channelMode: ChannelMode,
        oversamplingRatio: OversamplingRatio = .x8
    ) async throws -> AnalysisResult {
        if let cached = cache.load(url: url, channelMode: channelMode, oversamplingRatio: oversamplingRatio) {
            return cached
        }

        // Stage 1: Decode (AVAudioFile I/O — runs on calling actor, async by convention)
        currentStage = "Decoding audio..."; progress = 0.05
        let decoded = try await decoder.decode(url: url)

        // Stage 2: Derive channels (fast, on main actor)
        currentStage = "Deriving channels..."; progress = 0.15
        let channelData = ChannelDeriver.derive(from: decoded, mode: channelMode)

        // Stage 3–8: DSP — extract all values to locals before crossing actor boundary.
        // Struct copies (value semantics) are Sendable; KWeightingFilter is @unchecked Sendable.
        currentStage = "Applying K-weighting..."; progress = 0.25
        let kFilter = KWeightingFilter(sampleRate: decoded.sampleRate)
        let kWeighted = await Task.detached { [kFilter, channelData] in
            kFilter.processChannelData(channelData)
        }.value

        currentStage = "Measuring loudness..."; progress = 0.40
        let meter = LoudnessMeter()
        let sr = decoded.sampleRate
        let loudness = await Task.detached { [meter, kWeighted, sr] in
            meter.measure(kWeightedData: kWeighted, sampleRate: sr)
        }.value

        currentStage = "Measuring true peak..."; progress = 0.55
        let tpMeter = TruePeakMeter()
        let truePeakResult = await Task.detached { [tpMeter, channelData, sr, oversamplingRatio] in
            tpMeter.measure(channelData: channelData, sampleRate: sr, ratio: oversamplingRatio)
        }.value

        currentStage = "Analyzing spectrum..."; progress = 0.70
        let specMeter = SpectrumAnalyzer()
        let spectrum = await Task.detached { [specMeter, channelData, sr] in
            specMeter.analyze(channelData: channelData, sampleRate: sr)
        }.value

        currentStage = "Analyzing stereo field..."; progress = 0.80
        var stereoResult: StereoResult?
        if channelMode == .stereo, let right = decoded.right {
            let stereoMeter = StereoAnalyzer()
            let left = decoded.left
            stereoResult = await Task.detached { [stereoMeter, left, right, sr] in
                stereoMeter.analyze(left: left, right: right, sampleRate: sr)
            }.value
        }

        currentStage = "Computing dynamics..."; progress = 0.90
        let dynMeter = DynamicsAnalyzer()
        let dynamics = await Task.detached { [dynMeter, channelData, loudness, truePeakResult, sr] in
            dynMeter.analyze(
                channelData: channelData,
                loudness: loudness,
                truePeak: truePeakResult,
                sampleRate: sr
            )
        }.value

        currentStage = "Complete"; progress = 1.0

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
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false)),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        // Include modification date: two WAV files can share the same filename + size
        // (identical-length, same bit-depth re-renders), but differ in content.
        let modDate: Double
        if let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = rv.contentModificationDate {
            modDate = date.timeIntervalSince1970
        } else {
            modDate = 0
        }

        let input = "\(fileName)|\(fileSize)|\(modDate)|\(channelMode.rawValue)|\(oversamplingRatio.rawValue)"
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
