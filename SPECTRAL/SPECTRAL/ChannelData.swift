import Foundation

struct ChannelData {
    let channels: [[Float]]

    var isMono: Bool { channels.count == 1 }
    var left: [Float] { channels[0] }
    var right: [Float]? { channels.count > 1 ? channels[1] : nil }
}
