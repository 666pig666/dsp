import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ResultsView: View {
    let result: AnalysisResult
    @Binding var channelMode: ChannelMode
    @ObservedObject var comparisonStack: ComparisonStack
    var onAddFile: (([URL]) -> Void)?

    @State private var currentPage = 0
    @State private var showFileImporter = false

    private let pageTitles = [
        "SUMMARY", "LOUDNESS", "TRUE PEAK", "SPECTRUM", "STEREO", "DYNAMICS", "COMPLIANCE"
    ]

    private var availableModes: [ChannelMode] {
        result.metadata.channelCount == 1 ? [.stereo] : ChannelMode.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ComparisonPillBar(stack: comparisonStack)

            if comparisonStack.files.count > 1 {
                ComparisonSummaryTable(stack: comparisonStack)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Theme.bg0)
            }

            // Page title
            Text(pageTitles[currentPage])
                .font(.system(size: 11, weight: .semibold, design: .default))
                .tracking(2.0)
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .animation(.easeIn(duration: 0.3), value: currentPage)

            TabView(selection: $currentPage) {
                SummaryDashboardPage(result: result, navigateTo: $currentPage, comparisonStack: comparisonStack)
                    .tag(0)
                LoudnessPage(result: result, comparisonStack: comparisonStack)
                    .tag(1)
                TruePeakPage(result: result)
                    .tag(2)
                SpectrumPage(result: result, comparisonStack: comparisonStack)
                    .tag(3)
                StereoPage(result: result, comparisonStack: comparisonStack)
                    .tag(4)
                DynamicsPage(result: result, comparisonStack: comparisonStack)
                    .tag(5)
                CompliancePage(result: result, comparisonStack: comparisonStack)
                    .tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentPage) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }

            // Custom page indicators
            pageIndicators
                .padding(.vertical, 8)
        }
        .background(Theme.bg1)
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.metadata.fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            Picker("Mode", selection: $channelMode) {
                ForEach(availableModes, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)

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
                    .tint(Theme.accent)
            }

            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .tint(Theme.accent)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Custom page indicators

    private var pageIndicators: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(i == currentPage ? Theme.accent : Color(hex: 0x3A3A4A))
                    .frame(
                        width:  i == currentPage ? 8 : 6,
                        height: i == currentPage ? 8 : 6
                    )
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }
}
