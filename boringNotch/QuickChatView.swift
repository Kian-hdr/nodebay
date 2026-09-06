import AppKit
import SwiftUI
import NodebayMarkdown

struct QuickChatView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var chat = QuickChatCoordinator.shared
    @State private var editing = false
    @State private var reading = false
    @State private var holding = false
    @State private var composerInteraction = false
    @State private var transcriptInteraction = false
    @State private var showJumpToLatest = false
    @State private var jumpToLatestToken = 0
    @State private var interactionID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chat.messages.isEmpty && chat.pendingQuestion == nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text("How can I help?").font(.system(size: 16, weight: .medium))
                    Text("Ask a question, explore an idea, or draft a reply.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("\(chat.providerDisplayName) · \(chat.available ? "Online" : "Needs setup") · Temporary")
                        .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 3)
                    if !chat.available {
                        Text(chat.status.explanation)
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 3)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    QuickChatTranscriptView(messages: chat.messages, pendingQuestion: chat.pendingQuestion,
                        reading: $reading, showJumpToLatest: $showJumpToLatest,
                        jumpToLatestToken: jumpToLatestToken, reduceMotion: reduceMotion,
                        interactionChanged: { transcriptInteraction = $0; updateHold() }, userActivity: chat.userActivity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showJumpToLatest {
                        Button { jumpToLatestToken += 1 } label: {
                            Label("Latest", systemImage: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(6)
                        .help("Jump to latest reply")
                        .accessibilityLabel("Jump to latest reply")
                    }
                }
            }
            if chat.generating {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(chat.activeThinkDeeper ? "Thinking deeper…" : "Thinking…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
                .accessibilityElement(children: .combine)
            }
            if let error = chat.error {
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.leading, 8)
                    .accessibilityLabel("Chat status: \(error)")
            }
            if chat.useKnowledge {
                Label(UserDefaults.standard.string(forKey: "nodebay.quickChat.knowledgeName") ?? "Knowledge Folder", systemImage: "folder")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            QuickChatComposer(text: $chat.draft, editing: $editing,
                canSend: !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.available,
                generating: chat.generating, send: chat.send, stop: chat.stop,
                interactionChanged: { composerInteraction = $0; updateHold() }, userActivity: chat.userActivity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        // Focus, drafts and active generation are not window-visibility locks.
        .onDisappear { releaseHold() }
        .onExitCommand {
            editing = false; reading = false; releaseHold()
            NSApp.keyWindow?.makeFirstResponder(nil); vm.close()
        }
    }

    private func updateHold() {
        let shouldHold = composerInteraction || transcriptInteraction
        if shouldHold && !holding { SharingStateManager.shared.beginInteraction(); holding = true }
        if !shouldHold { releaseHold() }
        chat.interaction(shouldHold, source: interactionID)
    }
    private func releaseHold() {
        if holding { SharingStateManager.shared.endInteraction(); holding = false }
        chat.interaction(false, source: interactionID)
    }
}

/// Chat commands share the notch's existing chrome, not a second toolbar.
struct QuickChatHeaderActions: View {
    @ObservedObject private var chat = QuickChatCoordinator.shared
    @State private var handoff = false
    @State private var information = false
    @State private var handoffText = ""
    @State private var handoffMessage = ""
    @State private var holding = false
    @State private var menuTracking = false
    @State private var interactionID = UUID()

    var body: some View {
        Menu {
            Button("New Chat", systemImage: "square.and.pencil") { chat.newChat() }
            Button("Continue in Codex…", systemImage: "arrow.up.forward.app") {
                handoffText = chat.transcript + (chat.draft.isEmpty ? "" : "\n\nCurrent request:\n" + chat.draft)
                handoffMessage = ""; handoff = true
            }.disabled(chat.messages.isEmpty && chat.draft.isEmpty)
            Divider()
            Button("Copy Conversation", systemImage: "doc.on.doc") { copy(chat.transcript) }.disabled(chat.messages.isEmpty)
            Button("Save as Quick Note", systemImage: "note.text") { QuickNotesCoordinator.shared.saveText(chat.transcript) { _ in } }
                .disabled(chat.messages.isEmpty)
            Button("Explain More") { chat.draft = "Explain your last answer in more detail."; chat.send() }
                .disabled(chat.messages.isEmpty || chat.generating || !chat.draft.isEmpty)
            Toggle("Think Deeper for Next Message", isOn: $chat.thinkDeeper)
            Divider()
            Toggle("Use Knowledge Folder", isOn: $chat.useKnowledge)
                .disabled(!UserDefaults.standard.bool(forKey: "nodebay.quickChat.knowledgeConsent"))
            Button("About Quick Chat", systemImage: "info.circle") { information = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .fixedSize().foregroundStyle(.secondary)
        .help("Chat actions").accessibilityLabel("Chat actions")
        .popover(isPresented: $handoff, arrowEdge: .bottom) { handoffView }
        .popover(isPresented: $information, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Chat").font(.headline)
                Text(chat.mode == .openAIAPI
                    ? "Uses your saved OpenAI API key. Requests go directly to OpenAI and use your API billing and project limits."
                    : "Uses your existing Codex sign-in. Requests go directly to OpenAI and use your account limits.")
                Text("Conversations are temporary in Nodebay. Provider-side retention follows your account settings.")
                    .foregroundStyle(.secondary)
                Text("Think Deeper allows a longer reply and, for supported models, more reasoning for one message. It may take longer. The selected model and account settings stay unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Return to send · Shift-Return for a new line").font(.caption).foregroundStyle(.secondary)
            }.font(.callout).padding(16).frame(width: 300)
        }
        .onChange(of: handoff || information) { _, _ in updateHold() }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            menuTracking = true; chat.userActivity(); updateHold()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            menuTracking = false; updateHold()
        }
        .onDisappear { releaseHold() }
    }

    private var handoffView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue in Codex").font(.headline)
            Text("Review what will leave Quick Chat. Only this visible text is included, not hidden instructions or folder access.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $handoffText).frame(width: 400, height: 180)
            Text(handoffMessage).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Copy Context") { copy(handoffText); handoffMessage = "Copied. Paste into your chosen app." }
                Button("Open Codex") {
                    guard let url = URL(string: "codex://"),
                          let app = NSWorkspace.shared.urlForApplication(toOpen: url) else {
                        handoffMessage = "Codex is unavailable. Copy Context instead."; return
                    }
                    NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
                        Task { @MainActor in handoffMessage = error == nil ? "App opened. Paste the copied context yourself." : "Could not open the app. Your chat is still here." }
                    }
                }
            }
            Text("Automatic prefilled handoff is disabled until its destination and payload limits are verified. Opening an app does not transfer this chat.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }

    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func updateHold() {
        let active = handoff || information || menuTracking
        if active && !holding { SharingStateManager.shared.beginInteraction(); holding = true }
        if !active { releaseHold() }
        chat.interaction(active, source: interactionID)
    }
    private func releaseHold() {
        if holding { SharingStateManager.shared.endInteraction(); holding = false }
        chat.interaction(false, source: interactionID)
    }
}

/// Native selectable text and scrolling; never steals first responder on hover.
private struct QuickChatTranscriptView: NSViewRepresentable {
    let messages: [QuickChatMessage]
    let pendingQuestion: String?
    @Binding var reading: Bool
    @Binding var showJumpToLatest: Bool
    let jumpToLatestToken: Int
    let reduceMotion: Bool
    let interactionChanged: (Bool) -> Void
    let userActivity: () -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        let view = QuickChatTranscriptDocumentView()
        view.focusChanged = { reading = $0 }
        view.interactionChanged = interactionChanged
        view.onUserActivity = userActivity
        view.latestStateChanged = { unread in
            DispatchQueue.main.async { showJumpToLatest = unread }
        }
        view.setAccessibilityLabel("Quick Chat conversation")
        view.autoresizingMask = [.width]
        scroll.documentView = view
        view.attach(to: scroll)
        context.coordinator.lastJumpToken = jumpToLatestToken
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? QuickChatTranscriptDocumentView else { return }
        view.reduceMotion = reduceMotion
        view.update(QuickChatPolicy.displayMessages(messages, pendingQuestion: pendingQuestion)) { MarkdownRenderer.render($0) }
        if context.coordinator.lastJumpToken != jumpToLatestToken {
            context.coordinator.lastJumpToken = jumpToLatestToken
            view.jumpToLatest(animated: true)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastJumpToken = 0 }
}

extension BoringNotchWindow: QuickChatFocusWindow {
    func makeQuickChatFirstResponder(_ responder: NSResponder) { makeShelfItemFirstResponder(responder) }
}

extension BoringNotchSkyLightWindow: QuickChatFocusWindow {
    func makeQuickChatFirstResponder(_ responder: NSResponder) { makeShelfItemFirstResponder(responder) }
}

struct QuickChatSettingsSections: View {
    @ObservedObject private var chat = QuickChatCoordinator.shared
    @AppStorage("nodebay.quickChat.automaticTabs") private var automaticTabs = false
    @AppStorage("nodebay.quickChat.inactivityMinutes") private var inactivity = 180.0
    @AppStorage("nodebay.quickChat.apiModel") private var apiModel = QuickChatProviderMode.defaultAPIModel
    @AppStorage("nodebay.quickChat.knowledgeConsent") private var consent = false
    @AppStorage("nodebay.quickChat.knowledgeDefault") private var knowledgeDefault = false
    @AppStorage("nodebay.quickChat.knowledgeName") private var folderName = "None selected"
    @AppStorage("nodebay.quickChat.knowledgeIncluded") private var included = ""
    @AppStorage("nodebay.quickChat.knowledgeExcluded") private var excluded = ""
    @State private var knowledgeError = ""
    @State private var showConsent = false
    @State private var apiKey = ""
    var body: some View {
        Section("Quick Chat") {
            Picker("Mode", selection: Binding(get: { chat.mode }, set: { mode in
                chat.selectMode(mode)
                if mode == .off && BoringViewCoordinator.shared.currentView == .chat {
                    BoringViewCoordinator.shared.currentView = .home
                }
            })) {
                ForEach(QuickChatProviderMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Off is the default. When enabled, Quick Chat appears as a tab in the notch.")
                .font(.caption).foregroundStyle(.secondary)

            if chat.mode != .off {
                LabeledContent("Status", value: chat.status.availability.rawValue.capitalized)
                LabeledContent(chat.mode == .codexCLI ? "CLI version" : "Model", value: chat.status.version)
                Text(chat.status.explanation).foregroundStyle(.secondary)
                HStack {
                    Button(chat.mode == .openAIAPI ? "Validate Connection" : "Rescan CLI") {
                        Task { await chat.validateProvider() }
                    }
                    .disabled(chat.generating || chat.validating || (chat.mode == .openAIAPI && !chat.apiKeyStored))
                    if chat.validating { ProgressView().controlSize(.small) }
                }
            }
        }

        if chat.mode == .codexCLI {
            Section("Codex CLI") {
                Text("Uses the Codex CLI and your existing ChatGPT sign-in. Nodebay does not read or store your password. Requests still go to OpenAI and use your Codex account limits; this is not offline inference.")
                    .foregroundStyle(.secondary)
                LabeledContent("Answer delivery", value: "Complete replies")
                Text("Streaming remains disabled while the App Server tool-isolation gate is unresolved. The restricted CLI worker cannot use tools or modify files.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Official Codex setup", destination: URL(string: "https://learn.chatgpt.com/docs/quickstart")!)
            }
        }

        if chat.mode == .openAIAPI {
            Section("OpenAI API") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API key")
                        .font(.headline)
                    Text(chat.apiKeyStored
                         ? "Your key is saved. To replace it, paste a new key below."
                         : "Paste your OpenAI API key below, then click Save to Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SecureField("Paste API key here (⌘V)", text: $apiKey)
                        .labelsHidden()
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .accessibilityLabel("OpenAI API key")
                        .accessibilityHint("Paste your API key here, then save it to Keychain. The key stays hidden.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                HStack {
                    Button(chat.apiKeyStored ? "Replace Key" : "Save to Keychain") {
                        let submitted = apiKey
                        Task {
                            if await chat.saveAPIKey(submitted) { apiKey = "" }
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if chat.apiKeyStored {
                        Button("Remove Key", role: .destructive) { Task { await chat.removeAPIKey() } }
                    }
                }
                TextField("Model", text: $apiModel)
                    .disabled(chat.generating || chat.validating)
                    .onChange(of: apiModel) { _, _ in chat.reloadAPIConfiguration() }
                    .onSubmit { chat.reloadAPIConfiguration() }
                Text("The key is stored in this Mac's Keychain, never in preferences or logs. Validate Connection sends only a short test prompt and may incur a small API charge. API usage and billing are separate from ChatGPT subscriptions.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Manage OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
            }
        }

        if chat.mode != .off {
            Section("Conversation") {
            Toggle("Automatically choose a tab when opening", isOn: $automaticTabs)
            Text("Off preserves your existing default-tab preferences. Manual selection always wins while open.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Clear after \(Int(inactivity)) minutes of inactivity", value: $inactivity, in: 1...1440, step: 15)
                .onChange(of: inactivity) { _, _ in chat.userActivity() }
            Text("Closing the notch keeps your chat and draft. The default is three hours of inactivity; a reply in progress gets a fresh interval when it finishes. Only Nodebay's temporary chat is cleared, never saved notes or provider history.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Temporary in Nodebay. Conversation content stays in memory here, but submitted requests go to OpenAI through the selected provider. Provider-side retention is governed by that account. Nodebay does not promise provider-wide deletion.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Read Master Instructions") {
                if let url = Bundle.main.url(forResource: "QuickChatInstructions-v1", withExtension: "md") { NSWorkspace.shared.open(url) }
            }
            Text("Prefilled handoff is not yet verified. Copy Context is an explicit fallback.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Knowledge Folder (optional)") {
                LabeledContent("Read-only folder", value: folderName)
                Button("Choose Folder…") { chooseFolder() }
                Text("Choosing a folder grants local read access only. Enabling excerpts separately allows up to four small relevant passages to be sent to OpenAI with your question. The full folder is never uploaded. Documents may contain outdated or untrusted statements.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(consent ? "Disable Cloud Excerpts" : "Allow Relevant Excerpts…") {
                    if consent { consent = false; chat.useKnowledge = false } else { showConsent = true }
                }.disabled(UserDefaults.standard.data(forKey: "nodebay.quickChat.knowledgeBookmark") == nil)
                Toggle("Use folder by default in new chats", isOn: $knowledgeDefault).disabled(!consent)
                TextField("Include subfolders (one relative path per line; empty means all)", text: $included, axis: .vertical).lineLimit(1...3)
                TextField("Exclude subfolders (one relative path per line)", text: $excluded, axis: .vertical).lineLimit(1...3)
                Button("Disconnect Folder") {
                    chat.useKnowledge = false; consent = false; knowledgeDefault = false
                    UserDefaults.standard.removeObject(forKey: "nodebay.quickChat.knowledgeBookmark")
                    folderName = "None selected"; included = ""; excluded = ""
                }
                Text(knowledgeError).font(.caption).foregroundStyle(.secondary)
            }
        }
        .alert("Allow relevant excerpts to OpenAI?", isPresented: $showConsent) {
            Button("Cancel", role: .cancel) {}
            Button("Allow Excerpts") { consent = true }
        } message: { Text("Only when Knowledge Folder is enabled for a submitted question, Nodebay searches locally and sends small matching excerpts through your selected AI provider. Provider retention, billing and account limits apply. Folder access is never transferred to another app.") }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "nodebay.quickChat.knowledgeBookmark")
            folderName = url.lastPathComponent; consent = false; knowledgeDefault = false
            chat.useKnowledge = false; knowledgeError = ""
        } catch { knowledgeError = QuickChatKnowledgeError.permission.rawValue }
    }
}
