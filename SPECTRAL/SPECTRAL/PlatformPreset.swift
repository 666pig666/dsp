import Foundation

struct PlatformPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var targetIntegratedLUFS: Double
    var targetIntegratedTolerance: Double
    var maxTruePeakDBTP: Double
    var isBuiltIn: Bool

    static let builtInPresets: [PlatformPreset] = [
        PlatformPreset(
            id: UUID(), name: "Spotify",
            targetIntegratedLUFS: -14.0,
            targetIntegratedTolerance: 1.0,
            maxTruePeakDBTP: -1.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "Apple Music",
            targetIntegratedLUFS: -16.0,
            targetIntegratedTolerance: 1.0,
            maxTruePeakDBTP: -1.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "YouTube",
            targetIntegratedLUFS: -14.0,
            targetIntegratedTolerance: 1.0,
            maxTruePeakDBTP: -1.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "Amazon Music",
            targetIntegratedLUFS: -14.0,
            targetIntegratedTolerance: 1.0,
            maxTruePeakDBTP: -2.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "Tidal",
            targetIntegratedLUFS: -14.0,
            targetIntegratedTolerance: 1.0,
            maxTruePeakDBTP: -1.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "EBU R128 Broadcast",
            targetIntegratedLUFS: -23.0,
            targetIntegratedTolerance: 0.5,
            maxTruePeakDBTP: -1.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "ATSC A/85 (US Broadcast)",
            targetIntegratedLUFS: -24.0,
            targetIntegratedTolerance: 2.0,
            maxTruePeakDBTP: -2.0,
            isBuiltIn: true
        ),
        PlatformPreset(
            id: UUID(), name: "Podcast (Apple)",
            targetIntegratedLUFS: -16.0,
            targetIntegratedTolerance: 2.0,
            maxTruePeakDBTP: -1.0,
            isBuiltIn: true
        ),
    ]
}
