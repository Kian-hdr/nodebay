import AppKit
import SwiftUI

struct STLRepairProvider: ProcessingProvider {
    let descriptor = ProcessingProviderDescriptor(id: "stl-repair", name: "STL Repair · Blender",
        systemImage: "cube.transparent", purpose: "Inspect and repair separate STL copies without changing originals.",
        provider: "Blender Foundation", officialURL: URL(string: "https://www.blender.org/")!,
        license: "GPL-2.0-or-later (companion); Nodebay adapter GPL-3.0", runsLocally: true, requiresNetwork: false,
        inputTypes: ["Binary STL", "ASCII STL"], outputTypes: ["Binary STL", "Structural report"],
        pinnedVersion: STLRepairService.testedVersion, configurable: true)
    func diagnose() async -> EngineDiagnostic {
        do {
            let result = try await SafeProcessRunner.runApproved(engine: "stl-repair", executable: STLRepairService.executable, arguments: ["--version"], timeout: .seconds(8))
            let exact = result.standardOutput.components(separatedBy: .newlines).first == "Blender \(STLRepairService.testedVersion)"
            return .init(availability: result.exitCode == 0 && exact ? .installed : .error,
                         version: exact ? STLRepairService.testedVersion : "Unsupported or unavailable",
                         location: STLRepairService.executable.path,
                         message: exact ? "Pinned local companion ready. No network access." : "Install the tested Blender 5.0.1 companion. Other versions are not enabled.")
        } catch { return .unavailable(STLRepairError.unavailable.rawValue) }
    }
}

struct STLRepairEntry: Identifiable {
    let id = UUID()
    let sourceName: String
    let outputName: String?
    let report: STLRepairReport?
    let error: String?
}

@MainActor final class STLRepairCoordinator: ObservableObject {
    static let shared = STLRepairCoordinator()
    @Published private(set) var isRunning = false
    @Published private(set) var progress = "Ready"
    @Published private(set) var entries: [STLRepairEntry] = []
    @Published private(set) var lastError: String?
    @Published private(set) var sourceIDs: Set<UUID> = []
    private var task: Task<Void, Never>?
    private var reportWindow: NSWindow?
    private let service: STLRepairService
    private let defaults: UserDefaults
    init(service: STLRepairService = .shared, defaults: UserDefaults = .standard) { self.service = service; self.defaults = defaults }
    var defaultMode: STLRepairMode { STLRepairMode(rawValue: defaults.string(forKey: "nodebay.stlRepair.mode") ?? "safe") ?? .safe }
    func supports(_ item: ShelfItem) -> Bool {
        (item.stackMembers ?? [item]).contains { $0.fileURL.map(STLRepairService.supports) == true }
    }

    func start(_ item: ShelfItem, mode: STLRepairMode? = nil) { start(items: item.stackMembers ?? [item], beside: item, mode: mode ?? defaultMode) }

    func start(items: [ShelfItem], beside source: ShelfItem?, mode: STLRepairMode, automatic: Bool = false) {
        guard !isRunning else { showReport(); return }
        // Automatic mode is deliberately limited to conservative structural repair.
        guard !automatic || mode == .safe else { return }
        var confirmed = false
        if mode == .thorough {
            SharingStateManager.shared.beginInteraction()
            defer { SharingStateManager.shared.endInteraction() }
            let alert = NSAlert()
            alert.messageText = "Fill open boundaries in repaired copies?"
            alert.informativeText = "Thorough Repair may close large holes, including intentional openings, and change the model's surface. It does not delete components, remesh, simplify or rescale. Originals remain unchanged. Inspect the results in a slicer."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Repair Copies")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            confirmed = true
        }
        let compatible = items.filter { $0.fileURL.map(STLRepairService.supports) == true }
        guard !compatible.isEmpty else { return }
        guard compatible.count <= 50 else { lastError = "Repair at most 50 models per batch."; showReport(); return }
        isRunning = true; lastError = nil; entries = []
        sourceIDs = Set(compatible.map(\.id) + (source.map { [$0.id] } ?? []))
        let skipped = items.count - compatible.count
        progress = "Repairing 0 of \(compatible.count)"
        if !automatic { showReport() }
        task = Task {
            var outputs: [ShelfItem] = []
            defer { isRunning = false; sourceIDs = []; task = nil }
            for (index, item) in compatible.enumerated() {
                if Task.isCancelled { break }
                progress = "\(mode == .inspect ? "Inspecting" : "Repairing") \(index + 1) of \(compatible.count)"
                do {
                    guard let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else { throw STLRepairError.failed }
                    let result = try await service.process(url, mode: mode, confirmed: confirmed)
                    if let output = result.outputURL { outputs.append(ShelfItem(kind: .file(bookmark: try Bookmark(url: output).data))) }
                    entries.append(.init(sourceName: item.displayName, outputName: result.outputURL?.lastPathComponent, report: result.report, error: nil))
                } catch {
                    if Task.isCancelled { break }
                    let message = (error as? STLRepairError)?.rawValue ?? STLRepairError.failed.rawValue
                    lastError = message
                    entries.append(.init(sourceName: item.displayName, outputName: nil, report: nil, error: message))
                }
            }
            if !outputs.isEmpty {
                let result = source?.stackMembers != nil || compatible.count > 1
                    ? ShelfItem(kind: .stack(name: "Repaired Models", members: outputs)) : outputs[0]
                if let source { ShelfStateViewModel.shared.insertResult(result, beside: source) }
                else { ShelfStateViewModel.shared.add([result]) }
            }
            progress = "\(Task.isCancelled ? "Cancelled. " : "")\(entries.count) processed; \(outputs.count) copies; \(skipped) unsupported skipped."
            // Fixed redacted status only. No filenames, geometry, paths or model contents.
            defaults.set(lastError ?? "Completed locally", forKey: "nodebay.stlRepair.lastResult")
        }
    }

    func cancel() { task?.cancel(); progress = "Cancelling…" }

    func showReport() {
        if reportWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "STL Repair · Nodebay"
            window.contentView = NSHostingView(rootView: STLRepairReportView())
            window.isReleasedWhenClosed = false
            window.center(); reportWindow = window
        }
        reportWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct STLRepairReportView: View {
    @ObservedObject private var repair = STLRepairCoordinator.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(repair.progress).font(.headline)
                Spacer()
                if repair.isRunning { ProgressView().controlSize(.small); Button("Cancel", action: repair.cancel) }
            }
            if let error = repair.lastError { Text(error).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(repair.entries) { entry in
                        GroupBox(entry.sourceName) {
                            VStack(alignment: .leading, spacing: 5) {
                                if let output = entry.outputName { Text("Copy: \(output)").textSelection(.enabled) }
                                if let r = entry.report {
                                    Text(r.status == "partial" ? "Partially repaired; defects need attention" : r.status == "inspected" ? "Inspection complete; no copy created" : "Mesh structure repaired")
                                        .font(.headline)
                                    Text("Blender \(r.engine) · Local only")
                                    Text("Size: \(r.input_bytes) → \(r.output_bytes) bytes")
                                    Text("Triangles: \(r.before.triangles) → \(r.after.triangles); vertices: \(r.before.vertices) → \(r.after.vertices)")
                                    Text("Closed boundary loops: \(r.before.holes) → \(r.after.holes); holes closed: \(r.holes_closed)")
                                    Text("Boundary edges: \(r.before.boundary_edges) → \(r.after.boundary_edges)")
                                    Text("Non-manifold edges: \(r.before.non_manifold_edges) → \(r.after.non_manifold_edges)")
                                    Text("Removed: \(r.removed_duplicates) duplicate and \(r.removed_degenerate) degenerate faces")
                                    Text("Normal corrections: \(r.normals_corrected); winding defects: \(r.before.winding_edges) → \(r.after.winding_edges)")
                                    Text("Components: \(r.before.components) → \(r.after.components), preserved")
                                    Text("Remeshed: No. Scale changed: No. Surface/topology changed: \(r.geometry_changed ? "Yes" : "No")")
                                    Text("Self-intersections are not tested or repaired. Boundary loops are not proof of intentional holes. STL does not encode units.")
                                    ForEach(r.warnings, id: \.self) { Text("Warning: \($0.replacingOccurrences(of: "_", with: " "))") }
                                } else { Text(entry.error ?? "Repair failed") }
                            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Text("Printability still requires slicer and physical validation. Originals are unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(minWidth: 500, minHeight: 350)
    }
}

struct STLRepairConfigurationSections: View {
    @AppStorage("nodebay.stlRepair.mode") private var mode = STLRepairMode.safe.rawValue
    @AppStorage("nodebay.stlRepair.automatic") private var automatic = false
    @AppStorage("nodebay.stlRepair.lastResult") private var lastResult = "Not run"
    @ObservedObject private var repair = STLRepairCoordinator.shared
    @State private var testResult = "Not run"
    var body: some View {
        Section("STL Repair") {
            Picker("Default mode", selection: $mode) { ForEach(STLRepairMode.allCases) { Text($0.title).tag($0.rawValue) } }
            Toggle("Automatically Safe Repair newly added STL files", isOn: $automatic)
            Text("Off by default. Thorough Repair always requires confirmation. Files are limited to 32 MiB and 200,000 triangles; one engine runs at a time, with a 160-second timeout and 2 GiB peak-memory watchdog.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Local-only mode", value: "Always enabled")
            LabeledContent("Online provider", value: "Unavailable; no uploads implemented")
            Link("Install Blender 5.0.1 for Apple Silicon", destination: URL(string: "https://download.blender.org/release/Blender5.0/")!)
            Link("Repair engine source and licensing", destination: URL(string: "https://projects.blender.org/blender/blender/src/tag/v5.0.1")!)
            Button("Show Last Repair Report", action: repair.showReport)
            LabeledContent("Last redacted result", value: lastResult)
            LabeledContent("Test repair", value: testResult)
            Button("Test Local Repair") {
                testResult = "Running…"
                Task {
                    let source = FileManager.default.temporaryDirectory.appendingPathComponent("nodebay-stl-test-\(UUID()).stl")
                    defer { try? FileManager.default.removeItem(at: source) }
                    do {
                        // Deliberately open synthetic triangle: a partial repair is expected.
                        let fixture = "solid test\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid test\n"
                        try await Task.detached { try Data(fixture.utf8).write(to: source, options: .atomic) }.value
                        let result = try await STLRepairService.shared.process(source, mode: .safe)
                        testResult = result.report.after.triangles == 1 ? "Passed; open boundary correctly reported" : "Failed"
                        if let output = result.outputURL { try? FileManager.default.removeItem(at: output) }
                    } catch { testResult = "Failed; check Blender 5.0.1 installation and runtime diagnostics" }
                }
            }.disabled(repair.isRunning || testResult == "Running…")
        }
    }
}
