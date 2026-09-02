import SwiftUI
import AppKit

struct QuickNoteEditor: View {
    @ObservedObject private var notes = QuickNotesCoordinator.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Quick Note").font(.headline)
            Text("Markdown is saved locally. Up to 1 MiB of text.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .frame(width: 340, height: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .focused($focused)
                .accessibilityLabel("Quick Note text")
                .disabled(notes.isWorking)
            if let error = notes.diagnostic?.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { draft = ""; close() }.keyboardShortcut(.cancelAction)
                Button(notes.isWorking ? "Saving…" : "Save Note") {
                    notes.saveText(draft) { succeeded in
                        if succeeded { draft = ""; close() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(notes.isWorking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .onAppear { focused = true }
        .onDisappear { draft = "" }
    }
}

struct QuickNotesSettingsView: View {
    @AppStorage("nodebay.quickNotes.enabled") private var enabled = true
    @AppStorage("nodebay.quickNotes.filenameStyle") private var filenameStyle = "Readable timestamp"
    @AppStorage("nodebay.quickNotes.preferHeading") private var preferHeading = false
    @AppStorage("nodebay.quickNotes.richText") private var richText = true
    @AppStorage("nodebay.quickNotes.confirmation") private var confirmation = true
    @AppStorage("nodebay.quickNotes.addToShelf") private var addToShelf = true
    @ObservedObject private var notes = QuickNotesCoordinator.shared

    var body: some View {
        Form {
            Section("Quick Notes") {
                Toggle("Enable Quick Notes", isOn: $enabled)
                Text("Press Command-V inside an open notch to save copied text as Markdown. File URLs keep the file workflow; URL-only text uses the downloader. Paste inside an editor is unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Creation") {
                Picker("Default filename style", selection: $filenameStyle) {
                    Text("Readable timestamp").tag("Readable timestamp")
                    Text("Compact timestamp").tag("Compact timestamp")
                }
                Toggle("Prefer first heading as filename", isOn: $preferHeading)
                Text("Only generic headings such as Notes, Ideas, or Checklist are used. Other headings keep a timestamp so secrets and copied sentences do not become filenames.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Preserve rich-text formatting", isOn: $richText)
                Toggle("Show confirmation after creation", isOn: $confirmation)
                Toggle("Automatically add notes to the shelf", isOn: $addToShelf)
            }
            .disabled(!enabled)
            Section("Storage and Privacy") {
                LabeledContent("Default note location", value: "Nodebay-managed Quick Notes")
                Button("Show Notes Folder") {
                    Task {
                        do {
                            let directory = QuickNotesCoordinator.directory
                            try await Task.detached { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }.value
                            NSWorkspace.shared.open(directory)
                        } catch { /* Creation failures are surfaced during note saving. */ }
                    }
                }
                LabeledContent("Clipboard monitoring", value: "Never")
                LabeledContent("Processing", value: "Entirely on this Mac")
                Text("The clipboard is read only for an explicit paste. Text is limited to 1 MiB, rich data to 4 MiB per representation. Unsupported HTML falls back to plain text. Removing a shelf tile does not delete its file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                LabeledContent("Last result", value: notes.diagnostic.map { $0.succeeded ? "Success" : "Failure" } ?? "Not run")
                if let diagnostic = notes.diagnostic {
                    LabeledContent("Character count", value: String(diagnostic.characterCount))
                    LabeledContent("Clipboard representation", value: diagnostic.representation)
                    LabeledContent("Output category", value: diagnostic.locationCategory)
                    LabeledContent("Last redacted error", value: diagnostic.error ?? "None")
                }
                Text("No note contents, filenames, URLs, or clipboard history are logged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Quick Notes")
    }
}
