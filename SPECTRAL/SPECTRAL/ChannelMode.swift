import Foundation

enum ChannelMode: String, CaseIterable, Codable {
    case stereo = "Stereo"
    case leftOnly = "Left"
    case rightOnly = "Right"
    case mid = "Mid"
    case side = "Side"
}
