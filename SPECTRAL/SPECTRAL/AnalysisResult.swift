import Foundation

struct AnalysisResult: Codable, Identifiable {
    let id: UUID
    let metadata: AudioFileMetadata
    let channelMode: ChannelMode
    let loudness: LoudnessResult
    let truePeak: TruePeakResult
    let spectrum: SpectrumResult
    let stereo: StereoResult?
    let dynamics: DynamicsResult
    let analysisDate: Date
    let oversamplingRatio: Int
}
