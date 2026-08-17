import AppKit
import SwiftUI

struct PluginsEnginesSettingsView: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared

    var body: some View {
        Form {
            Section {
                Text("Processing integrations are registered providers with explicit privacy, network, version, and licensing metadata.")
                    .foregroundStyle(.secondary)
            }

            ForEach(registry.providers) { provider in
                EngineProviderSection(provider: provider, diagnostic: registry.diagnostics[provider.id])
            }

            Section {
                HStack {
                    if let lastRefresh = registry.lastRefresh {
                        Text("Last checked \(lastRefresh.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Diagnostics") {
                        Task { await registry.refresh() }
                    }
                    .disabled(registry.isRefreshing)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Plugins & Engines")
        .task { await registry.refresh() }
    }
}

struct ConvertersSettingsView: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared
    @State private var testState = "Not tested"
    @State private var isTesting = false

    private var converters: [AnyProcessingProvider] {
        registry.providers.filter { $0.id == "markitdown" }
    }

    var body: some View {
        Form {
            Section {
                Text("Converters create new collision-safe output files. Nodebay never modifies or replaces an original input file.")
                    .foregroundStyle(.secondary)
            }

            ForEach(converters) { provider in
                EngineProviderSection(provider: provider, diagnostic: registry.diagnostics[provider.id])
            }

            Section("Microsoft MarkItDown Test") {
                LabeledContent("Test conversion", value: testState)
                Button(isTesting ? "Testing…" : "Run Local Test Conversion") {
                    runTestConversion()
                }
                .disabled(isTesting)
                Text("The test uses generated text in a temporary file. Runtime diagnostics retain status and error type only, never document contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Converters")
        .task { await registry.refresh() }
    }

    private func runTestConversion() {
        isTesting = true
        testState = "Running"
        Task {
            let source = FileManager.default.temporaryDirectory
                .appending(path: "nodebay-runtime-test-\(UUID().uuidString).txt")
            var output: URL?
            do {
                try Data("Nodebay local runtime test".utf8).write(to: source, options: .atomic)
                output = try await MarkItDownConversionService.shared.convert(source)
                let outputSize = try output?.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                testState = outputSize > 0 ? "Passed" : "Failed: empty output"
            } catch {
                testState = "Failed: \(error.localizedDescription)"
            }
            try? FileManager.default.removeItem(at: source)
            if let output {
                TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: output)
            }
            isTesting = false
            await registry.refresh()
        }
    }
}

struct ImageCompressionSettingsView: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared
    @AppStorage("nodebay.imageOptim.automaticEnabled") private var automaticEnabled = false
    @AppStorage("nodebay.imageOptim.thresholdMB") private var thresholdMB = 10.0
    @AppStorage("nodebay.imageOptim.askBeforeCompression") private var askBeforeCompression = true
    @AppStorage("nodebay.imageOptim.resultSuffix") private var resultSuffix = "optimized"
    @AppStorage("nodebay.imageOptim.addResults") private var addResults = true

    private var diagnostic: EngineDiagnostic? { registry.diagnostics["imageoptim"] }

    var body: some View {
        Form {
            Section("ImageOptim Companion") {
                LabeledContent("Status", value: diagnostic?.availability.rawValue ?? "Checking")
                LabeledContent("Version", value: diagnostic?.version ?? "Checking")
                LabeledContent("Installation", value: "/Applications/ImageOptim.app")
                Link("Download ImageOptim", destination: URL(string: "https://imageoptim.com/mac")!)
                Button("Open ImageOptim Preferences") {
                    NSWorkspace.shared.open(ImageOptimCompressionService.appURL)
                }
                .disabled(!ImageOptimCompressionService.isInstalled)
                Text("Nodebay invokes ImageOptim’s documented blocking executable with structured file arguments. Only a collision-safe copy is provided to ImageOptim.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Picker("Compression mode", selection: .constant("ImageOptim preferences")) {
                    Text("ImageOptim preferences").tag("ImageOptim preferences")
                }
                Toggle("Ask before compression", isOn: $askBeforeCompression)
                TextField("Result filename suffix", text: $resultSuffix)
                LabeledContent("Result location", value: "Beside the original")
                Toggle("Automatically add results to Nodebay", isOn: $addResults)
                LabeledContent("Metadata preservation", value: "Controlled in ImageOptim")
            }

            Section("Automatic Compression") {
                Toggle("Enable automatic compression", isOn: $automaticEnabled)
                HStack {
                    Text("Minimum image size")
                    Spacer()
                    TextField("MB", value: $thresholdMB, format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 70)
                    Text("MB").foregroundStyle(.secondary)
                }
                .disabled(!automaticEnabled)
                Text("Automatic compression is off by default and never runs without explicit opt-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                LabeledContent("Last result", value: diagnostic?.message ?? "Not checked")
                Button("Run Diagnostics") { Task { await registry.refresh() } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Image Compressor")
        .task { await registry.refresh() }
    }
}

private struct EngineProviderSection: View {
    let provider: AnyProcessingProvider
    let diagnostic: EngineDiagnostic?

    private var descriptor: ProcessingProviderDescriptor { provider.descriptor }

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: descriptor.systemImage)
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.name).font(.headline)
                    Text(descriptor.purpose).foregroundStyle(.secondary)
                }
                Spacer()
                EngineStatusBadge(availability: diagnostic?.availability ?? .unavailable)
            }

            LabeledContent("Status", value: diagnostic?.availability.rawValue ?? "Checking")
            LabeledContent("Version", value: diagnostic?.version ?? descriptor.pinnedVersion ?? "Checking")
            if let pinned = descriptor.pinnedVersion {
                LabeledContent("Pinned version", value: pinned)
            }
            LabeledContent("Provider", value: descriptor.provider)
            LabeledContent("License", value: descriptor.license)
            LabeledContent("Processing", value: descriptor.runsLocally ? "Local" : "External")
            LabeledContent("Network", value: descriptor.requiresNetwork ? "Required for its task" : "Not required")
            LabeledContent("Inputs", value: descriptor.inputTypes.joined(separator: ", "))
            LabeledContent("Outputs", value: descriptor.outputTypes.joined(separator: ", "))
            LabeledContent("Runtime", value: diagnostic?.location ?? "Checking")

            if let message = diagnostic?.message, !message.isEmpty {
                LabeledContent("Diagnostics", value: message)
            }

            HStack {
                Link("Official project", destination: descriptor.officialURL)
                Spacer()
                Link("Third-party notices", destination: NodebayBrand.sourceURL.appending(path: "blob/feature/nodebay/THIRD_PARTY_NOTICES_NODEBAY.md"))
            }
        } header: {
            Text(descriptor.name)
        }
    }
}

private struct EngineStatusBadge: View {
    let availability: EngineAvailability

    private var color: Color {
        switch availability {
        case .bundled, .installed: .green
        case .unavailable: .secondary
        case .error: .red
        }
    }

    var body: some View {
        Text(availability.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}
