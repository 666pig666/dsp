import Foundation

struct AudioFileMetadata: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let url: URL
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int64
    let duration: TimeInterval
    let formatDescription: String
}
