//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var downloadCoordinator = DownloadCoordinator.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var showsAddLink = false
    @State private var linkDraft = ""
    @State private var addLinkInteractionActive = false
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        .overlay(alignment: .bottom) {
            if tvm.canUndoRemoval {
                HStack(spacing: 8) {
                    Text("Removed from Nodebay")
                    Button("Undo") { tvm.undoLastRemoval() }
                        .keyboardShortcut("z", modifiers: .command)
                    Button {
                        dismissRemovalNotice()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss removal notification")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
                .padding(.bottom, 6)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            let distance = hypot(value.translation.width, value.translation.height)
                            if distance >= 24 {
                                dismissRemovalNotice()
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
            }
        }
        .animation(.easeOut(duration: 0.18), value: tvm.canUndoRemoval)
        .onChange(of: vm.notchState) { _, _ in
            tvm.dismissRemovalNotice()
        }
        .onChange(of: showsAddLink) { _, isPresented in
            if isPresented {
                beginAddLinkInteractionIfNeeded()
            } else {
                endAddLinkInteractionIfNeeded()
            }
        }
        .onDisappear {
            endAddLinkInteractionIfNeeded()
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }

    private func dismissRemovalNotice() {
        withAnimation(.easeOut(duration: 0.18)) {
            tvm.dismissRemovalNotice()
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    if showsAddLink {
                        showsAddLink = false
                    } else {
                        // The popover is a separate window outside the notch's
                        // hover region, so acquire the lease before presenting.
                        beginAddLinkInteractionIfNeeded()
                        showsAddLink = true
                    }
                } label: {
                    Image(systemName: "link.badge.plus")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(8)
                .help("Add media link")
                .accessibilityLabel("Add media download link")
                .popover(isPresented: $showsAddLink, arrowEdge: .top) {
                    addLinkPopover
                }
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    private var addLinkPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Download").font(.headline)
            Text("Paste one or more HTTP or HTTPS media links.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $linkDraft)
                .font(.body)
                .frame(width: 320, height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .accessibilityLabel("Media links")
            HStack {
                Spacer()
                Button("Cancel") { showsAddLink = false }
                    .keyboardShortcut(.cancelAction)
                Button("Inspect") {
                    let urls = MediaDownloaderService.validatedURLs(in: linkDraft)
                    guard !urls.isEmpty else { return }
                    downloadCoordinator.add(urls: urls)
                    linkDraft = ""
                    showsAddLink = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(MediaDownloaderService.validatedURLs(in: linkDraft).isEmpty)
            }
        }
        .padding(14)
    }

    private func beginAddLinkInteractionIfNeeded() {
        guard !addLinkInteractionActive else { return }
        addLinkInteractionActive = true
        SharingStateManager.shared.beginInteraction()
    }

    private func endAddLinkInteractionIfNeeded() {
        guard addLinkInteractionActive else { return }
        addLinkInteractionActive = false
        SharingStateManager.shared.endInteraction()
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: spacing) {
                        ForEach(Defaults[.reverseShelfOrdering] ? tvm.items.reversed() : tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
