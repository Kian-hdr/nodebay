import AppKit
import SwiftUI

private enum EngineSettingsArea: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case documents = "Documents"
    case images = "Images"

    var id: Self { self }
}

struct PluginsEnginesSettingsView: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared
    @State private var selectedArea: EngineSettingsArea = .overview

    var body: some View {
        Form {
            Section {
                Picker("Engine settings", selection: $selectedArea) {
                    ForEach(EngineSettingsArea.allCases) { area in
                        Text(area.rawValue).tag(area)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(areaDescription)
                    .foregroundStyle(.secondary)
            }

            switch selectedArea {
            case .overview:
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
            case .documents:
                MarkItDownConfigurationSections()
            case .images:
                ImageCompressionConfigurationSections()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Plugins & Engines")
        .task { await registry.refresh() }
    }

    private var areaDescription: String {
        switch selectedArea {
        case .overview:
            "Review every processing engine, its health, version, privacy behavior, and license."
        case .documents:
            "Configure and test local document-to-Markdown conversion. Originals are never modified."
        case .images:
            "Configure ImageOptim safe-copy compression. Original images are never passed to ImageOptim."
        }
    }
}

private struct MarkItDownConfigurationSections: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared
    @State private var testState = "Not tested"
    @State private var isTesting = false

    private var diagnostic: EngineDiagnostic? { registry.diagnostics["markitdown"] }

    var body: some View {
        Group {
            Section("Microsoft MarkItDown") {
                LabeledContent("Status", value: diagnostic?.availability.rawValue ?? "Checking")
                LabeledContent("Version", value: diagnostic?.version ?? "Checking")
                LabeledContent("Processing", value: "Local only")
                LabeledContent("Output", value: "Separate collision-safe Markdown copy")
                Link("Official project", destination: URL(string: "https://github.com/microsoft/markitdown")!)
            }

            Section("Test Conversion") {
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

private struct ImageCompressionConfigurationSections: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared
    @AppStorage("nodebay.imageOptim.automaticEnabled") private var automaticEnabled = false
    @AppStorage("nodebay.imageOptim.thresholdMB") private var thresholdMB = 10.0
    @AppStorage("nodebay.imageOptim.askBeforeCompression") private var askBeforeCompression = true
    @AppStorage("nodebay.imageOptim.resultSuffix") private var resultSuffix = "optimized"

    private var diagnostic: EngineDiagnostic? { registry.diagnostics["imageoptim"] }

    var body: some View {
        Group {
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
                LabeledContent("Completed results", value: "Always added to Nodebay")
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
    }
}

struct DownloaderSettingsView: View {
    @StateObject private var registry = ProcessingProviderRegistry.shared
    @AppStorage("nodebay.downloader.defaultFormat") private var defaultFormat = MediaDownloadFormat.bestOriginal.rawValue
    @AppStorage("nodebay.downloader.askEveryTime") private var askEveryTime = true
    @AppStorage("nodebay.downloader.preferredResolution") private var preferredResolution = "Best available"
    @AppStorage("nodebay.downloader.audioBitrate") private var audioBitrate = "Best available"
    @AppStorage("nodebay.downloader.maximumConcurrent") private var maximumConcurrent = 2
    @AppStorage("nodebay.downloader.filenameTemplate") private var filenameTemplate = "Title and media ID"
    @AppStorage("nodebay.downloader.preserveMetadata") private var preserveMetadata = true
    @AppStorage("nodebay.downloader.preserveThumbnail") private var preserveThumbnail = false
    @AppStorage("nodebay.downloader.askPlaylist") private var askPlaylist = true
    @State private var input = ""
    @State private var status = "Ready"
    @State private var isWorking = false
    @State private var inspections: [MediaInspection] = []
    @State private var workTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Add Download") {
                TextField("One or more HTTP/HTTPS URLs", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { inspectInput() }
                HStack {
                    Button(isWorking ? "Working…" : "Inspect URL") { inspectInput() }
                        .disabled(isWorking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !inspections.isEmpty {
                        Button("Download \(inspections.count == 1 ? "Item" : "\(inspections.count) Items")") { startDownloads() }
                            .disabled(isWorking)
                    }
                    if isWorking {
                        Button("Cancel") {
                            workTask?.cancel()
                            status = "Cancelled"
                            isWorking = false
                        }
                    }
                }
                LabeledContent("Status", value: status)
                Text("Inspection and downloads run locally. Network connections go directly from yt-dlp on this Mac to the source service.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Download Location") {
                LabeledContent("Directory", value: displayPath(configuredDirectory()))
                Button("Choose Custom Directory…") { chooseDirectory() }
                Text("Custom folders use a persistent security-scoped bookmark. Nodebay never writes outside the selected directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Formats") {
                Picker("Default format", selection: $defaultFormat) {
                    ForEach(MediaDownloadFormat.allCases) { format in Text(format.rawValue).tag(format.rawValue) }
                }
                Toggle("Ask every time", isOn: $askEveryTime)
                Picker("Preferred resolution", selection: $preferredResolution) {
                    ForEach(["Best available", "2160p", "1440p", "1080p", "720p"], id: \.self) { Text($0) }
                }
                Picker("Preferred audio bitrate", selection: $audioBitrate) {
                    ForEach(["Best available", "320 kbps", "256 kbps", "192 kbps", "128 kbps"], id: \.self) { Text($0) }
                }
                Stepper("Maximum simultaneous downloads: \(maximumConcurrent)", value: $maximumConcurrent, in: 1...4)
            }

            Section("Output") {
                Picker("Filename template", selection: $filenameTemplate) {
                    Text("Title and media ID").tag("Title and media ID")
                }
                Toggle("Preserve metadata", isOn: $preserveMetadata)
                Toggle("Preserve thumbnail", isOn: $preserveThumbnail)
                LabeledContent("Completed downloads", value: "Always added to Nodebay")
                Toggle("Ask before downloading a playlist", isOn: $askPlaylist)
            }

            Section("Privacy and Safety") {
                LabeledContent("Browser cookies", value: "Disabled")
                LabeledContent("Nodebay proxy or cloud", value: "None")
                Text("Only HTTP and HTTPS URLs are accepted. Nodebay uses structured process arguments, disables yt-dlp config files and plugins, and does not expose arbitrary command-line options. Users remain responsible for permissions, copyright, and service terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Runtime Diagnostics") {
                LabeledContent("yt-dlp", value: registry.diagnostics["yt-dlp"]?.version ?? "Checking")
                LabeledContent("FFmpeg", value: registry.diagnostics["ffmpeg"]?.version ?? "Checking")
                Button("Run Diagnostics") { Task { await registry.refresh() } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Downloader")
        .task { await registry.refresh() }
    }

    private func inspectInput() {
        workTask?.cancel()
        isWorking = true
        status = "Inspecting"
        inspections = []
        workTask = Task {
            do {
                let rawURLs = input.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !rawURLs.isEmpty else { throw MediaDownloaderError.invalidURL }
                for (index, rawURL) in rawURLs.enumerated() {
                    try Task.checkCancellation()
                    status = "Inspecting \(index + 1) of \(rawURLs.count)"
                    let url = try MediaDownloaderService.validatedURL(from: rawURL)
                    inspections.append(try await MediaDownloaderService.shared.inspect(url))
                }
                let playlists = inspections.filter(\.isPlaylist).count
                status = "Ready: \(inspections.count) item\(inspections.count == 1 ? "" : "s")\(playlists > 0 ? ", \(playlists) playlist\(playlists == 1 ? "" : "s")" : "")"
            } catch is CancellationError {
                status = "Cancelled"
            } catch {
                status = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func startDownloads() {
        guard !inspections.isEmpty else { return }
        let playlistCount = inspections.filter(\.isPlaylist).count
        if playlistCount > 0, askPlaylist {
            let alert = NSAlert()
            alert.messageText = "Download playlist content?"
            alert.informativeText = "\(playlistCount) inspected URL\(playlistCount == 1 ? " is" : "s are") a playlist. Each playlist item will be downloaded as a separate file."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        workTask?.cancel()
        isWorking = true
        workTask = Task {
            var files: [URL] = []
            var failures: [String] = []
            let destination = configuredDirectory()
            let accessed = destination.startAccessingSecurityScopedResource()
            defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
            let format = MediaDownloadFormat(rawValue: defaultFormat) ?? .bestOriginal
            for (index, inspection) in inspections.enumerated() {
                if Task.isCancelled { break }
                status = "Downloading \(index + 1) of \(inspections.count)"
                do {
                    let result = try await MediaDownloaderService.shared.download(
                        inspection,
                        format: format,
                        destination: destination,
                        playlistConfirmed: true,
                        preserveMetadata: preserveMetadata,
                        preserveThumbnail: preserveThumbnail
                    )
                    files.append(contentsOf: result.files)
                } catch {
                    failures.append("\(inspection.title): \(error.localizedDescription)")
                }
            }
            if !files.isEmpty {
                do {
                    let shelfItems = try files.map { ShelfItem(kind: .file(bookmark: try Bookmark(url: $0).data)) }
                    if shelfItems.count == 1 {
                        ShelfStateViewModel.shared.add(shelfItems)
                    } else {
                        ShelfStateViewModel.shared.add([ShelfItem(kind: .stack(name: "Downloaded Media", members: shelfItems))])
                    }
                } catch {
                    failures.append("Nodebay could not add a completed file to the shelf: \(error.localizedDescription)")
                }
            }
            status = Task.isCancelled
                ? "Cancelled. Completed files were preserved."
                : "Completed \(files.count) file\(files.count == 1 ? "" : "s")\(failures.isEmpty ? "" : "; \(failures.count) failed")"
            isWorking = false
        }
    }

    private func configuredDirectory() -> URL {
        if let data = UserDefaults.standard.data(forKey: "nodebay.downloader.directoryBookmark"),
           let url = Bookmark(data: data).resolvedURL {
            return url
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    }

    private func displayPath(_ url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Download Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try Bookmark(url: url)
            UserDefaults.standard.set(bookmark.data, forKey: "nodebay.downloader.directoryBookmark")
            status = "Download folder saved"
        } catch {
            status = "Folder access failed: \(error.localizedDescription)"
        }
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
                Link("Third-party notices", destination: NodebayBrand.sourceURL.appending(path: "blob/dev/THIRD_PARTY_NOTICES.md"))
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
