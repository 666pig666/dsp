import SwiftUI
import UniformTypeIdentifiers

struct FileImportView: View {
    @StateObject private var viewModel = FileImportViewModel()
    @StateObject private var pipeline = AnalysisPipeline()
    @State private var analysisResult: AnalysisResult?
    @State private var channelMode: ChannelMode = .stereo
    @State private var showValidation = false
    @State private var versionTapCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if let result = analysisResult {
                    ResultsView(result: result, channelMode: $channelMode)
                } else if pipeline.progress > 0 && pipeline.progress < 1.0 {
                    analysisProgress
                } else {
                    mainContent
                }
            }
            .background(Color(hex: 0x0D0D0D))
            .navigationTitle("SPECTRAL")
            .toolbar {
                if analysisResult == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.showFileImporter = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                if analysisResult != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            analysisResult = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
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
                if let file = viewModel.importedFiles.last {
                    analyzeFile(url: file.url, mode: newMode)
                }
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

    private var analysisProgress: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: pipeline.progress)
                .tint(Color(hex: 0x00D4FF))
                .frame(width: 200)
            Text(pipeline.currentStage)
                .font(.caption)
                .foregroundStyle(Color(hex: 0x888888))
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: 0x00D4FF))
            Text("No Audio Files")
                .font(.title2)
                .foregroundStyle(Color(hex: 0xE0E0E0))
            Text("Import audio files to begin analysis")
                .font(.subheadline)
                .foregroundStyle(Color(hex: 0x888888))
            Button {
                viewModel.showFileImporter = true
            } label: {
                Label("Import Audio File", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x00D4FF))
            Spacer()

            // Version label with hidden developer mode trigger
            Text("SPECTRAL v1.0")
                .font(.caption2)
                .foregroundStyle(Color(hex: 0x333333))
                .onTapGesture(count: 3) {
                    showValidation = true
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var fileList: some View {
        List {
            ForEach(viewModel.importedFiles) { file in
                Button {
                    analyzeFile(url: file.url, mode: channelMode)
                } label: {
                    MetadataRow(metadata: file)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func analyzeFile(url: URL, mode: ChannelMode) {
        Task {
            do {
                let result = try await pipeline.analyze(url: url, channelMode: mode)
                analysisResult = result
            } catch {
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
    }
}

struct MetadataRow: View {
    let metadata: AudioFileMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metadata.fileName)
                .font(.headline)
                .foregroundStyle(Color(hex: 0xE0E0E0))

            HStack(spacing: 16) {
                metadataItem(label: "Sample Rate", value: formatSampleRate(metadata.sampleRate))
                metadataItem(label: "Channels", value: metadata.channelCount == 1 ? "Mono" : "Stereo")
            }

            HStack(spacing: 16) {
                metadataItem(label: "Duration", value: formatDuration(metadata.duration))
                metadataItem(label: "Frames", value: "\(metadata.frameCount)")
            }

            Text(metadata.formatDescription)
                .font(.caption2)
                .foregroundStyle(Color(hex: 0x888888))
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(hex: 0x1A1A2E))
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color(hex: 0x888888))
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color(hex: 0xE0E0E0))
        }
    }

    private func formatSampleRate(_ rate: Double) -> String {
        if rate >= 1000 {
            return String(format: "%.1f kHz", rate / 1000.0)
        }
        return String(format: "%.0f Hz", rate)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 100)
        return String(format: "%d:%02d.%02d", minutes, secs, ms)
    }
}
