import Foundation
import AVFoundation
import UniformTypeIdentifiers

@MainActor
class FileImportViewModel: ObservableObject {
    @Published var importedFiles: [AudioFileMetadata] = []
    @Published var showFileImporter = false
    @Published var errorMessage: String?
    @Published var showError = false

    func importFiles(urls: [URL]) {
        for url in urls {
            do {
                let metadata = try readMetadata(from: url)
                if metadata.channelCount > 2 {
                    errorMessage = "SPECTRAL v1 supports mono and stereo files only."
                    showError = true
                    continue
                }
                importedFiles.append(metadata)
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func readMetadata(from url: URL) throws -> AudioFileMetadata {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "SPECTRAL", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot access file."])
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.fileFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let frameCount = Int64(audioFile.length)
        let duration = Double(frameCount) / sampleRate
        let formatDesc = String(describing: format)

        return AudioFileMetadata(
            id: UUID(),
            fileName: url.lastPathComponent,
            url: url,
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameCount: frameCount,
            duration: duration,
            formatDescription: formatDesc
        )
    }
}
