import Foundation
import Accelerate

struct ChannelDeriver {
    static func derive(from audio: DecodedAudio, mode: ChannelMode) -> ChannelData {
        let left = audio.left
        guard let right = audio.right else {
            return ChannelData(channels: [left])
        }

        switch mode {
        case .stereo:
            return ChannelData(channels: [left, right])

        case .leftOnly:
            return ChannelData(channels: [left])

        case .rightOnly:
            return ChannelData(channels: [right])

        case .mid:
            let mid = computeMid(left: left, right: right)
            return ChannelData(channels: [mid])

        case .side:
            let side = computeSide(left: left, right: right)
            return ChannelData(channels: [side])
        }
    }

    static func availableModes(for audio: DecodedAudio) -> [ChannelMode] {
        if audio.right == nil {
            return [.stereo]
        }
        return ChannelMode.allCases
    }

    private static func computeMid(left: [Float], right: [Float]) -> [Float] {
        let count = min(left.count, right.count)
        var result = [Float](repeating: 0, count: count)
        // mid = (L + R) / 2
        vDSP_vadd(left, 1, right, 1, &result, 1, vDSP_Length(count))
        var scalar: Float = 0.5
        vDSP_vsmul(result, 1, &scalar, &result, 1, vDSP_Length(count))
        return result
    }

    private static func computeSide(left: [Float], right: [Float]) -> [Float] {
        let count = min(left.count, right.count)
        var result = [Float](repeating: 0, count: count)
        // side = (L - R) / 2
        vDSP_vsub(right, 1, left, 1, &result, 1, vDSP_Length(count))
        var scalar: Float = 0.5
        vDSP_vsmul(result, 1, &scalar, &result, 1, vDSP_Length(count))
        return result
    }
}
