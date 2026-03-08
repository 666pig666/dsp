import Foundation

class ExportManager {
    func exportCSV(results: [AnalysisResult]) -> String {
        let header = [
            "fileName", "format", "sampleRate", "channelCount", "duration",
            "integratedLUFS", "momentaryMaxLUFS", "shortTermMaxLUFS", "LRA",
            "maxTruePeakDBTP", "truePeakL", "truePeakR", "oversamplingRatio",
            "PLR", "avgCrestFactor", "minCrestFactor", "rmsDBFS",
            "avgCorrelation", "minCorrelation", "midSideRatioDB"
        ].joined(separator: ";")

        var rows = [header]

        for result in results {
            let truePeakL = result.truePeak.perChannelTruePeakDBTP.first ?? -Double.infinity
            let truePeakR = result.truePeak.perChannelTruePeakDBTP.count > 1
                ? result.truePeak.perChannelTruePeakDBTP[1]
                : -Double.infinity

            let row = [
                result.metadata.fileName,
                result.metadata.formatDescription,
                String(format: "%.0f", result.metadata.sampleRate),
                "\(result.metadata.channelCount)",
                String(format: "%.3f", result.metadata.duration),
                String(format: "%.1f", result.loudness.integratedLUFS),
                String(format: "%.1f", result.loudness.momentaryMaxLUFS),
                String(format: "%.1f", result.loudness.shortTermMaxLUFS),
                String(format: "%.1f", result.loudness.loudnessRangeLU),
                String(format: "%.1f", result.truePeak.maxTruePeakDBTP),
                String(format: "%.1f", truePeakL),
                String(format: "%.1f", truePeakR),
                "\(result.truePeak.oversamplingRatio)",
                String(format: "%.1f", result.dynamics.plrDB),
                String(format: "%.1f", result.dynamics.averageCrestFactor),
                String(format: "%.1f", result.dynamics.minimumCrestFactor),
                String(format: "%.1f", result.dynamics.rmsSummedDBFS),
                String(format: "%.3f", result.stereo?.averageCorrelation ?? 0),
                String(format: "%.3f", result.stereo?.minimumCorrelation ?? 0),
                String(format: "%.1f", result.stereo?.midSideRatioDB ?? 0)
            ].joined(separator: ";")

            rows.append(row)
        }

        return rows.joined(separator: "\n")
    }

    func exportXML(results: [AnalysisResult], primaryId: UUID?) -> String {
        let primary = results.first { $0.id == primaryId } ?? results.first

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<spectral_analysis>\n"
        if let p = primary {
            xml += "  <primary>\(escapeXML(p.metadata.fileName))</primary>\n"
        }

        for result in results {
            let isPrimary = result.id == primary?.id
            let role = isPrimary ? "primary" : "comparison"
            xml += "  <file name=\"\(escapeXML(result.metadata.fileName))\" role=\"\(role)\">\n"

            xml += "    <metadata>\n"
            xml += "      <sampleRate>\(result.metadata.sampleRate)</sampleRate>\n"
            xml += "      <channelCount>\(result.metadata.channelCount)</channelCount>\n"
            xml += "      <duration>\(String(format: "%.3f", result.metadata.duration))</duration>\n"
            xml += "      <frameCount>\(result.metadata.frameCount)</frameCount>\n"
            xml += "    </metadata>\n"

            xml += "    <loudness>\n"
            xml += "      <integrated unit=\"LUFS\">\(String(format: "%.1f", result.loudness.integratedLUFS))</integrated>\n"
            xml += "      <momentaryMax unit=\"LUFS\">\(String(format: "%.1f", result.loudness.momentaryMaxLUFS))</momentaryMax>\n"
            xml += "      <shortTermMax unit=\"LUFS\">\(String(format: "%.1f", result.loudness.shortTermMaxLUFS))</shortTermMax>\n"
            xml += "      <loudnessRange unit=\"LU\">\(String(format: "%.1f", result.loudness.loudnessRangeLU))</loudnessRange>\n"
            xml += "    </loudness>\n"

            xml += "    <truePeak>\n"
            xml += "      <max unit=\"dBTP\">\(String(format: "%.1f", result.truePeak.maxTruePeakDBTP))</max>\n"
            xml += "      <oversamplingRatio>\(result.truePeak.oversamplingRatio)</oversamplingRatio>\n"
            for (i, chPeak) in result.truePeak.perChannelTruePeakDBTP.enumerated() {
                let chName = i == 0 ? "left" : "right"
                xml += "      <channel name=\"\(chName)\" unit=\"dBTP\">\(String(format: "%.1f", chPeak))</channel>\n"
            }
            xml += "    </truePeak>\n"

            xml += "    <dynamics>\n"
            xml += "      <plr unit=\"dB\">\(String(format: "%.1f", result.dynamics.plrDB))</plr>\n"
            xml += "      <avgCrestFactor unit=\"dB\">\(String(format: "%.1f", result.dynamics.averageCrestFactor))</avgCrestFactor>\n"
            xml += "      <minCrestFactor unit=\"dB\">\(String(format: "%.1f", result.dynamics.minimumCrestFactor))</minCrestFactor>\n"
            xml += "      <rmsSummed unit=\"dBFS\">\(String(format: "%.1f", result.dynamics.rmsSummedDBFS))</rmsSummed>\n"
            xml += "    </dynamics>\n"

            if let stereo = result.stereo {
                xml += "    <stereo>\n"
                xml += "      <avgCorrelation>\(String(format: "%.3f", stereo.averageCorrelation))</avgCorrelation>\n"
                xml += "      <minCorrelation>\(String(format: "%.3f", stereo.minimumCorrelation))</minCorrelation>\n"
                xml += "      <midSideRatio unit=\"dB\">\(String(format: "%.1f", stereo.midSideRatioDB))</midSideRatio>\n"
                xml += "    </stereo>\n"
            }

            // Emit <delta> for comparison files so consumers can diff relative to primary
            // without re-computing. All values are (this - primary); negative = lower than primary.
            if !isPrimary, let p = primary {
                let dIntegrated = result.loudness.integratedLUFS      - p.loudness.integratedLUFS
                let dTP         = result.truePeak.maxTruePeakDBTP     - p.truePeak.maxTruePeakDBTP
                let dLRA        = result.loudness.loudnessRangeLU     - p.loudness.loudnessRangeLU
                let dPLR        = result.dynamics.plrDB               - p.dynamics.plrDB
                let dCrest      = result.dynamics.averageCrestFactor  - p.dynamics.averageCrestFactor
                let dRMS        = result.dynamics.rmsSummedDBFS       - p.dynamics.rmsSummedDBFS
                let dCorr       = (result.stereo?.averageCorrelation  ?? 0) - (p.stereo?.averageCorrelation ?? 0)

                xml += "    <delta relative_to=\"\(escapeXML(p.metadata.fileName))\">\n"
                xml += "      <integrated unit=\"LUFS\" delta=\"\(String(format: "%+.2f", dIntegrated))\"/>\n"
                xml += "      <truePeak    unit=\"dBTP\" delta=\"\(String(format: "%+.2f", dTP))\"/>\n"
                xml += "      <lra         unit=\"LU\"   delta=\"\(String(format: "%+.2f", dLRA))\"/>\n"
                xml += "      <plr         unit=\"dB\"   delta=\"\(String(format: "%+.2f", dPLR))\"/>\n"
                xml += "      <crestFactor unit=\"dB\"   delta=\"\(String(format: "%+.2f", dCrest))\"/>\n"
                xml += "      <rms         unit=\"dBFS\" delta=\"\(String(format: "%+.2f", dRMS))\"/>\n"
                if result.stereo != nil && p.stereo != nil {
                    xml += "      <correlation delta=\"\(String(format: "%+.3f", dCorr))\"/>\n"
                }
                xml += "    </delta>\n"
            }

            xml += "  </file>\n"
        }

        xml += "</spectral_analysis>\n"
        return xml
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
