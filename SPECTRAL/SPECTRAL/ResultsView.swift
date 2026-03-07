import SwiftUI
import UniformTypeIdentifiers

struct ResultsView: View {
    let result: AnalysisResult
    @Binding var channelMode: ChannelMode
    @State private var currentPage = 0
    @State private var showFileImporter = false
    var onAddFile: (([URL]) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            // Paged content
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

            Picker("Mode", selection: $channelMode) {
                ForEach(ChannelMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(Color(hex: 0x00D4FF))

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
