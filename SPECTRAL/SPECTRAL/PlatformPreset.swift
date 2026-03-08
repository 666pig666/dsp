import Foundation

struct PlatformPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var targetIntegratedLUFS: Double
    var targetIntegratedTolerance: Double
    var maxTruePeakDBTP: Double
    var isBuiltIn: Bool

    // Primary source of presets. Loads PlatformPresets.json from the app bundle so
    // the list is editable without recompiling; falls back to hardcoded values if the
    // file is missing or corrupt (e.g. in unit-test targets that don't copy resources).
    static let builtInPresets: [PlatformPreset] = loadFromBundle() ?? hardcodedPresets

    // Intermediate DTO — the JSON omits the UUID and isBuiltIn fields; both are
    // synthesised on load. This keeps the JSON human-readable and avoids leaking
    // internal IDs into a file that developers may hand-edit.
    private struct PresetDTO: Decodable {
        let name: String
        let targetIntegratedLUFS: Double
        let targetIntegratedTolerance: Double
        let maxTruePeakDBTP: Double
    }

    private static func loadFromBundle() -> [PlatformPreset]? {
        guard let url = Bundle.main.url(forResource: "PlatformPresets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dtos = try? JSONDecoder().decode([PresetDTO].self, from: data),
              !dtos.isEmpty
        else { return nil }

        return dtos.map { dto in
            PlatformPreset(
                id: UUID(),
                name: dto.name,
                targetIntegratedLUFS: dto.targetIntegratedLUFS,
                targetIntegratedTolerance: dto.targetIntegratedTolerance,
                maxTruePeakDBTP: dto.maxTruePeakDBTP,
                isBuiltIn: true
            )
        }
    }

    // Fallback used when the bundle resource is unavailable.
    private static let hardcodedPresets: [PlatformPreset] = [
        PlatformPreset(id: UUID(), name: "Spotify",
                       targetIntegratedLUFS: -14.0, targetIntegratedTolerance: 1.0,
                       maxTruePeakDBTP: -1.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "Apple Music",
                       targetIntegratedLUFS: -16.0, targetIntegratedTolerance: 1.0,
                       maxTruePeakDBTP: -1.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "YouTube",
                       targetIntegratedLUFS: -14.0, targetIntegratedTolerance: 1.0,
                       maxTruePeakDBTP: -1.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "Amazon Music",
                       targetIntegratedLUFS: -14.0, targetIntegratedTolerance: 1.0,
                       maxTruePeakDBTP: -2.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "Tidal",
                       targetIntegratedLUFS: -14.0, targetIntegratedTolerance: 1.0,
                       maxTruePeakDBTP: -1.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "EBU R128 Broadcast",
                       targetIntegratedLUFS: -23.0, targetIntegratedTolerance: 0.5,
                       maxTruePeakDBTP: -1.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "ATSC A/85 (US Broadcast)",
                       targetIntegratedLUFS: -24.0, targetIntegratedTolerance: 2.0,
                       maxTruePeakDBTP: -2.0, isBuiltIn: true),
        PlatformPreset(id: UUID(), name: "Podcast (Apple)",
                       targetIntegratedLUFS: -16.0, targetIntegratedTolerance: 2.0,
                       maxTruePeakDBTP: -1.0, isBuiltIn: true),
    ]
}
