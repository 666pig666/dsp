import SwiftUI
import UniformTypeIdentifiers

struct ResultsView: View {
    let result: AnalysisResult
    @Binding var channelMode: ChannelMode
    @ObservedObject var comparisonStack: ComparisonStack
    var onAddFile: (([URL]) -> Void)?

    @State private var currentPage = 0
    @State private var showFileImporter = false

    // Only show modes that are valid for this file's channel count.
    // Mono files only expose .stereo (which runs as mono pass-through in ChannelDeriver).
    private var availableModes: [ChannelMode] {
        result.metadata.channelCount == 1 ? [.stereo] : ChannelMode.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // Comparison pill bar + summary table appear above the paged content
            // whenever two or more files are loaded.
            ComparisonPillBar(stack: comparisonStack)

            if comparisonStack.files.count > 1 {
                ComparisonSummaryTable(stack: comparisonStack)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0x0D0D0D))
            }

            TabView(selection: $currentPage) {
                SummaryDashboardPage(result: result, navigateTo: $currentPage)
                    .tag(0)
                LoudnessPage(result: result)
                    .tag(1)
                TruePeakPage(result: result)
                    .tag(2)
                SpectrumPage(result: result)
                    .tag(3)
                StereoPage(result: result)
                    .tag(4)
                DynamicsPage(result: result)
                    .tag(5)
                CompliancePage(result: result)
                    .tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
        .background(Color(hex: 0x0D0D0D))
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.audio],
            allowsMultipleSelection: true
        ) { fileResult in
            if case .success(let urls) = fileResult {
                onAddFile?(urls)
            }
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.metadata.fileName)
                    .font(.headline)
                    .foregroundStyle(Color(hex: 0xE0E0E0))
                    .lineLimit(1)
            }

            Spacer()

            // Channel mode picker, filtered to modes valid for this file.
            Picker("Mode", selection: $channelMode) {
                ForEach(availableModes, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(Color(hex: 0x00D4FF))

            // Export menu — CSV and XML via system share sheet.
            Menu {
                let exporter = ExportManager()
                ShareLink(
                    "Export CSV",
                    item: exporter.exportCSV(results: comparisonStack.files),
                    preview: SharePreview("\(result.metadata.fileName).csv")
                )
                ShareLink(
                    "Export XML",
                    item: exporter.exportXML(results: comparisonStack.files, primaryId: result.id),
                    preview: SharePreview("\(result.metadata.fileName).xml")
                )
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .tint(Color(hex: 0x00D4FF))
            }

            // Add comparison file.
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .tint(Color(hex: 0x00D4FF))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(hex: 0x1A1A2E))
    }
}
