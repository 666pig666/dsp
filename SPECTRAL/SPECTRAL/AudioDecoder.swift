import Foundation
import AVFoundation

class AudioDecoder {
    private let chunkSize: AVAudioFrameCount = 65536

    func decode(url: URL) async throws -> DecodedAudio {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.fileFormat
        let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: format.channelCount,
            interleaved: false
        )

        guard let processingFormat = processingFormat else {
            throw AudioDecoderError.unsupportedFormat
        }

        // Keep totalFrames as Int64 to avoid silent UInt32 truncation on files
        // longer than ~24 hours at 48 kHz. Cast to AVAudioFrameCount only for
        // the per-chunk read call below.
        let totalFrames: Int64 = audioFile.length
        let channelCount = Int(format.channelCount)

        var leftSamples = [Float]()
        leftSamples.reserveCapacity(Int(min(totalFrames, Int64(Int.max))))

        var rightSamples: [Float]? = channelCount > 1 ? [Float]() : nil
        rightSamples?.reserveCapacity(Int(min(totalFrames, Int64(Int.max))))

        let estimatedPCMBytes = totalFrames * Int64(channelCount) * 4
        if estimatedPCMBytes > 200 * 1024 * 1024 {
            throw AudioDecoderError.fileTooLarge
        }

        var framesRead: Int64 = 0
        while framesRead < totalFrames {
            let framesToRead = AVAudioFrameCount(min(Int64(chunkSize), totalFrames - framesRead))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: framesToRead) else {
                throw AudioDecoderError.bufferCreationFailed
            }

            try audioFile.read(into: buffer, frameCount: framesToRead)

            guard let floatData = buffer.floatChannelData else {
                throw AudioDecoderError.noFloatData
            }

            let count = Int(buffer.frameLength)
            let leftPointer = floatData[0]
            leftSamples.append(contentsOf: UnsafeBufferPointer(start: leftPointer, count: count))

            if channelCount > 1 {
                let rightPointer = floatData[1]
                rightSamples?.append(contentsOf: UnsafeBufferPointer(start: rightPointer, count: count))
            }

            framesRead += Int64(framesToRead)
        }

        let metadata = AudioFileMetadata(
            id: UUID(),
            fileName: url.lastPathComponent,
            url: url,
            sampleRate: format.sampleRate,
            channelCount: channelCount,
            frameCount: totalFrames,
            duration: Double(totalFrames) / format.sampleRate,
            formatDescription: String(describing: format)
        )

        return DecodedAudio(
            metadata: metadata,
            sampleRate: format.sampleRate,
            channelCount: channelCount,
            left: leftSamples,
            right: rightSamples
        )
    }
}

enum AudioDecoderError: LocalizedError {
    case unsupportedFormat
    case bufferCreationFailed
    case noFloatData
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported audio format."
        case .bufferCreationFailed: return "Failed to create audio buffer."
        case .noFloatData: return "No float channel data available."
        case .fileTooLarge: return "File is too large. Decoded PCM would exceed 200 MB."
        }
    }
}
