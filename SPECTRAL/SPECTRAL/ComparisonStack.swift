import Foundation

class ComparisonStack: ObservableObject {
    @Published var files: [AnalysisResult] = []
    @Published var alignmentWarning: String?

    var primary: AnalysisResult? { files.first }

    func add(_ result: AnalysisResult) throws {
        guard files.count < 4 else {
            throw ComparisonError.maximumFilesReached
        }
        files.append(result)
        checkAlignment()
    }

    func remove(id: UUID) {
        files.removeAll { $0.id == id }
        checkAlignment()
    }

    func promote(id: UUID) {
        guard let idx = files.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        let file = files.remove(at: idx)
        files.insert(file, at: 0)
    }

    func deltas() -> [ComparisonDelta] {
        guard let primary = primary, files.count > 1 else { return [] }
        return files.dropFirst().map { file in
            ComparisonDelta(
                fileId: file.id,
                fileName: file.metadata.fileName,
                deltaIntegratedLUFS: file.loudness.integratedLUFS - primary.loudness.integratedLUFS,
                deltaTruePeakDBTP: file.truePeak.maxTruePeakDBTP - primary.truePeak.maxTruePeakDBTP,
                deltaLRA: file.loudness.loudnessRangeLU - primary.loudness.loudnessRangeLU,
                deltaPLR: file.dynamics.plrDB - primary.dynamics.plrDB,
                deltaCorrelation: (file.stereo?.averageCorrelation ?? 0) - (primary.stereo?.averageCorrelation ?? 0),
                deltaCrestFactor: file.dynamics.averageCrestFactor - primary.dynamics.averageCrestFactor,
                deltaRMS: file.dynamics.rmsSummedDBFS - primary.dynamics.rmsSummedDBFS
            )
        }
    }

    private func checkAlignment() {
        guard files.count > 1 else {
            alignmentWarning = nil
            return
        }

        let sampleRate = files[0].metadata.sampleRate
        let frameCounts = files.map { $0.metadata.frameCount }
        let maxDiff = frameCounts.map { abs($0 - frameCounts[0]) }.max() ?? 0

        // Spec Section 12: warn only when files differ by more than 4096 samples.
        if maxDiff > 4096 {
            let ms = Int(Double(maxDiff) / sampleRate * 1000)
            alignmentWarning = "Files differ in length by \(ms) ms. Comparison may not be meaningful."
        } else {
            alignmentWarning = nil
        }
    }

    // 0xFF00FF (pure magenta) is too easily confused with cyan under deuteranopia.
    // Spec specifies 0xFF3399 (pink-magenta) for file C.
    static let fileColors: [UInt] = [0xFFFFFF, 0x00D4FF, 0xFF3399, 0xFFB800]
}

struct ComparisonDelta {
    let fileId: UUID
    let fileName: String
    let deltaIntegratedLUFS: Double
    let deltaTruePeakDBTP: Double
    let deltaLRA: Double
    let deltaPLR: Double
    let deltaCorrelation: Double
    let deltaCrestFactor: Double
    let deltaRMS: Double
}

enum ComparisonError: LocalizedError {
    case maximumFilesReached

    var errorDescription: String? {
        "Maximum 4 files allowed in comparison."
    }
}
