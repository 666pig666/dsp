import SwiftUI

struct ValidationView: View {
    @StateObject private var harness = ValidationHarness()

    var body: some View {
        NavigationStack {
            List {
                if harness.isRunning {
                    HStack {
                        ProgressView()
                        Text("Running validation tests...")
                            .foregroundStyle(Color(hex: 0x888888))
                    }
                }

                ForEach(harness.results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.passed ? Color(hex: 0x00CC66) : Color(hex: 0xFF3366))
                            Text(result.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(hex: 0xE0E0E0))
                        }
                        Text(result.details)
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0x888888))
                    }
                    .listRowBackground(Color(hex: 0x1A1A2E))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x0D0D0D))
            .navigationTitle("Validation")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Run") {
                        Task {
                            await harness.runAll()
                        }
                    }
                    .disabled(harness.isRunning)
                }
            }
        }
    }
}
