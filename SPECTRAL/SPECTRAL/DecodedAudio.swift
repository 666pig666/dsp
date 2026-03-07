import Foundation

struct DecodedAudio {
    let metadata: AudioFileMetadata
    let sampleRate: Double
    let channelCount: Int
    let left: [Float]
    let right: [Float]?
}
