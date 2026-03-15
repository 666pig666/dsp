import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FileImportView: View {
    @StateObject private var viewModel = FileImportViewModel()
    @StateObject private var pipeline = AnalysisPipeline()
    @StateObject private var comparisonStack = ComparisonStack()
    @State private var channelMode: ChannelMode = .stereo
    @State private var currentFileURL: URL?
    @State private var showValidation = false

    var body: some View {
        NavigationStack {
            Group {
                if let result = comparisonStack.primary {
                    ResultsView(
                        result: result,
                        channelMode: $channelMode,
                        comparisonStack: comparisonStack,
                        onAddFile: addComparisonFiles
                    )
                } else if pipeline.progress > 0 && pipeline.progress < 1.0 {
                    analysisProgress
                } else {
                    mainContent
                }
            }
            .background(Theme.bg1)
            .navigationTitle("SPECTRAL")
            .toolbar {
                if comparisonStack.primary == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.showFileImporter = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .tint(Theme.accent)
                    }
                }
                if comparisonStack.primary != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            comparisonStack.files.removeAll()
                            currentFileURL = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .tint(Theme.accent)
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: [UTType.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.importFiles(urls: urls)
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .sheet(isPresented: $showValidation) {
                ValidationView()
            }
            .onChange(of: channelMode) { _, newMode in
                if let url = currentFileURL {
                    analyzeFile(url: url, mode: newMode)
                }
            }
            .onAppear {
                pipeline.pruneCache()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if viewModel.importedFiles.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
    }

    // MARK: - Analysis progress bar

    private var analysisProgress: some View {
        VStack(spacing: 12) {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.bg3)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * max(0, min(1, pipeline.progress)), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: pipeline.progress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 48)
            Text(pipeline.currentStage)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .background(Theme.bg1)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            WaveformAnimation()
                .frame(width: 200, height: 24)

            Text("SPECTRAL")
                .font(.system(size: 28, weight: .bold, design: .default))
                .tracking(3.0)
                .foregroundStyle(Theme.textPrimary)

            Text("Audio Analysis Engine")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.textSecondary)

            Button {
                viewModel.showFileImporter = true
            } label: {
                Text("IMPORT FILE")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.bg0)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("SPECTRAL v1.0")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .onTapGesture(count: 3) {
                    showValidation = true
                }
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - File list

    private var fileList: some View {
        List {
            ForEach(viewModel.importedFiles) { file in
                Button {
                    analyzeFile(url: file.url, mode: channelMode)
                } label: {
                    MetadataRow(metadata: file)
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg1)
    }

    // MARK: - Actions

    private func analyzeFile(url: URL, mode: ChannelMode) {
        currentFileURL = url
        Task {
            do {
                let result = try await pipeline.analyze(url: url, channelMode: mode)
                comparisonStack.files = [result]
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
    }

    private func addComparisonFiles(urls: [URL]) {
        for url in urls {
            Task {
                do {
                    let result = try await pipeline.analyze(url: url, channelMode: channelMode)
                    try? comparisonStack.add(result)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                }
            }
        }
    }
}

// MARK: - WaveformAnimation

private struct WaveformAnimation: View {
    @State private var phase: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: mid))
            for x in stride(from: 0.0, through: size.width, by: 1.0) {
                let y = mid + 2.5 * sin((x / size.width) * 2 * .pi * 4 + phase)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(path, with: .color(Theme.accent.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
}

// MARK: - MetadataRow

struct MetadataRow: View {
    let metadata: AudioFileMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metadata.fileName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 6) {
                metadataPill(formatSampleRate(metadata.sampleRate))
                metadataPill(metadata.channelCount == 1 ? "Mono" : "Stereo")
                metadataPill(formatDuration(metadata.duration))
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.bg2)
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.bg3)
            .clipShape(Capsule())
    }

    private func formatSampleRate(_ rate: Double) -> String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000.0) : String(format: "%.0f Hz", rate)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
