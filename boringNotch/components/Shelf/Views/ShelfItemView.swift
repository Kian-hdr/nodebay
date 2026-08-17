//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import SwiftUI
import Defaults
import UniformTypeIdentifiers

import QuickLook

struct ShelfItemView: View {
    let item: ShelfItem
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var selection = ShelfSelectionModel.shared
    @ObservedObject private var shelfState = ShelfStateViewModel.shared
    @StateObject private var viewModel: ShelfItemViewModel
    @EnvironmentObject private var quickLookService: QuickLookService
    @State private var showStack = false
    @State private var debouncedDropTarget = false

    private var isSelected: Bool { viewModel.isSelected }
    private var shouldHideDuringDrag: Bool { selection.isDragging && selection.isSelected(item.id) && false }
    private var conversionTint: Color { Color(red: 0.24, green: 0.56, blue: 0.96) }
    private var showsActionButton: Bool {
        viewModel.canConvertToMarkdown || viewModel.canCompressImage || viewModel.canDownloadMedia
            || viewModel.canBatchConvertStack || viewModel.canBatchCompressStack
    }
    
    init(item: ShelfItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: ShelfItemViewModel(item: item))
    }

    var body: some View {
        ZStack {
            if !shouldHideDuringDrag {
                VStack(alignment: .center, spacing: 6) {
                    ZStack {
                        VStack(alignment: .center, spacing: 2) {
                            iconView
                            textView
                        }

                        DraggableClickHandler(
                            item: item,
                            viewModel: viewModel,
                            dragPreviewContent: {
                                DragPreviewView(thumbnail: viewModel.thumbnail ?? item.icon, displayName: item.displayName)
                            },
                            onRightClick: viewModel.handleRightClick,
                            onClick: { event, nsview in
                                viewModel.handleClick(event: event, view: nsview)
                                if item.stackMembers != nil,
                                   event.clickCount == 1,
                                   event.modifierFlags.intersection([.shift, .command, .control]).isEmpty {
                                    showStack = true
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 105, height: 88)
                    .offset(y: showsActionButton ? 0 : 13)

                    if showsActionButton {
                        conversionButton
                    } else {
                        Color.clear
                            .frame(height: 20)
                    }
                }
                .frame(width: 105, height: 114, alignment: .top)
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
                .background(backgroundView)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.1), value: debouncedDropTarget)
                .animation(.easeInOut(duration: 0.1), value: isSelected)

                Button {
                    ShelfStateViewModel.shared.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .offset(x: 48, y: -56)
                .help("Remove from Nodebay. The file stays on disk.")
                .accessibilityLabel("Remove \(item.displayName) from Nodebay")
            } else {
                Color.clear
                    .frame(width: 105, height: 114)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 5)
            }
        }
        .onChange(of: viewModel.isDropTargeted) { _, targeted in
            vm.dragDetectorTargeting = targeted
            // Debounce drop target state changes
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                debouncedDropTarget = targeted
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
            Task {
                let dropped = await ShelfDropService.items(from: providers)
                _ = ShelfStateViewModel.shared.createStack(onto: item, droppedItems: dropped)
            }
            return true
        }
        .popover(isPresented: $showStack, arrowEdge: .bottom) {
            if item.stackMembers != nil {
                StackContentsPopoverView(stack: item, viewModel: viewModel)
            }
        }
        .onAppear {
            Task { 
                await viewModel.loadThumbnail()
            }
            viewModel.onQuickLookRequest = { urls in
                quickLookService.show(urls: urls, selectFirst: true)
            }
        }
    }

    // MARK: - View Components

    private var iconView: some View {
        Image(nsImage: viewModel.thumbnail ?? item.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
            .overlay {
                if shelfState.isConverting(item) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.62))
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let members = item.stackMembers {
                    Text("\(members.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue, in: Capsule())
                        .accessibilityLabel("\(members.count) files")
                }
            }
    }

    private var textView: some View {
        Text(item.displayName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(height: 30, alignment: .top)
    }

    private var conversionButton: some View {
        Button {
            if item.stackMembers != nil {
                showStack = true
            } else if viewModel.canCompressImage {
                viewModel.compressImage()
            } else if viewModel.canDownloadMedia {
                viewModel.downloadMedia()
            } else {
                viewModel.convertItemToMarkdown()
            }
        } label: {
            HStack(spacing: 3) {
                if shelfState.isConverting(item) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(conversionTint.opacity(0.85))
                } else {
                    Image(systemName: viewModel.canDownloadMedia ? "arrow.down.circle" : (viewModel.canCompressImage ? "photo.badge.arrow.down" : "doc.badge.arrow.up"))
                }

                Text(actionButtonTitle)
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(conversionTint.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(conversionTint.opacity(0.1))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(conversionTint.opacity(0.35), lineWidth: 0.75)
                    }
            )
        }
        .frame(height: 20)
        .buttonStyle(.plain)
        .disabled(shelfState.isConverting(item))
        .help(viewModel.canDownloadMedia ? "Download media locally" : "Create a separate output copy")
        .accessibilityLabel(actionButtonTitle)
    }

    private var actionButtonTitle: String {
        if let progress = shelfState.conversionProgress[item.id] { return progress }
        if shelfState.isConverting(item) { return "Converting…" }
        if item.stackMembers != nil { return "Stack Actions" }
        if viewModel.canDownloadMedia { return "Download Media" }
        return viewModel.canCompressImage ? "Compress Image" : "Convert to MD"
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        lineWidth: strokeWidth
                    )
            )
    }

    private var backgroundColor: Color {
        if debouncedDropTarget {
            return Color.accentColor.opacity(0.25)
        } else if isSelected {
            return Color.accentColor.opacity(0.15)
        } else {
            return Color.clear
        }
    }

    private var strokeColor: Color {
        if debouncedDropTarget {
            return Color.accentColor.opacity(0.9)
        } else if isSelected {
            return Color.accentColor.opacity(0.8)
        } else {
            return Color.clear
        }
    }

    private var strokeWidth: CGFloat {
        if debouncedDropTarget {
            return 3
        } else if isSelected {
            return 2
        } else {
            return 1
        }
    }
}

private struct StackContentsPopoverView: View {
    let stack: ShelfItem
    @ObservedObject var viewModel: ShelfItemViewModel
    @EnvironmentObject private var quickLookService: QuickLookService
    @State private var name: String

    init(stack: ShelfItem, viewModel: ShelfItemViewModel) {
        self.stack = stack
        self.viewModel = viewModel
        _name = State(initialValue: stack.displayName)
    }

    private var members: [ShelfItem] { stack.stackMembers ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Stack name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { ShelfStateViewModel.shared.renameStack(stack, name: name) }
                    .accessibilityLabel("Stack name")
                Text("\(members.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        HStack(spacing: 8) {
                            Image(nsImage: member.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                            Text(member.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                if let url = member.fileURL {
                                    quickLookService.show(urls: [url], selectFirst: true)
                                }
                            } label: {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .disabled(member.fileURL == nil)
                            .help("Quick Look")

                            Button {
                                ShelfStateViewModel.shared.reorderMember(in: stack, from: index, to: index - 1)
                            } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Move earlier")

                            Button {
                                ShelfStateViewModel.shared.reorderMember(in: stack, from: index, to: index + 1)
                            } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == members.count - 1)
                            .help("Move later")

                            Button {
                                ShelfStateViewModel.shared.removeMember(member, from: stack)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove from stack and keep in Nodebay")
                        }
                        .padding(6)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onDrag { itemProvider(for: member) }
                    }
                }
            }
            .frame(maxHeight: 250)

            if viewModel.canBatchConvertStack {
                HStack {
                    Button("Convert Compatible Files to MD") {
                        viewModel.convertStackToMarkdown()
                    }
                    .disabled(viewModel.isBatchConverting)
                    if viewModel.isBatchConverting {
                        Button("Cancel", role: .cancel) { viewModel.cancelBatchConversion() }
                    }
                }
            }

            if viewModel.canBatchCompressStack {
                HStack {
                    Button("Compress Compatible Images") {
                        viewModel.compressStackImages()
                    }
                    .disabled(viewModel.isBatchConverting)
                    if viewModel.isBatchConverting {
                        Button("Cancel", role: .cancel) { viewModel.cancelBatchConversion() }
                    }
                }
            }

            HStack {
                Button("Dissolve Stack") { ShelfStateViewModel.shared.dissolveStack(stack) }
                Spacer()
                Button("Save Name") { ShelfStateViewModel.shared.renameStack(stack, name: name) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    private func itemProvider(for member: ShelfItem) -> NSItemProvider {
        switch member.kind {
        case .file:
            if let url = member.fileURL { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: member.displayName as NSString)
        case .text(let string):
            return NSItemProvider(object: string as NSString)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .stack:
            return NSItemProvider()
        }
    }
}

// MARK: - Draggable Click Handler with NSDraggingSource
private struct DraggableClickHandler<Content: View>: NSViewRepresentable {
    let item: ShelfItem
    let viewModel: ShelfItemViewModel
    @ViewBuilder let dragPreviewContent: () -> Content
    let onRightClick: (NSEvent, NSView) -> Void
    let onClick: (NSEvent, NSView) -> Void
    
    func makeNSView(context: Context) -> DraggableClickView {
        let view = DraggableClickView()
        view.item = item
        view.viewModel = viewModel
        view.getDragPreview = {
            self.renderDragPreview()
        }
        view.onRightClick = onRightClick
        view.onClick = onClick
        return view
    }
    
    func updateNSView(_ nsView: DraggableClickView, context: Context) {
        nsView.item = item
        nsView.viewModel = viewModel
        // Update the closure to capture latest state if needed, though usually content closure is enough
        nsView.getDragPreview = {
            self.renderDragPreview()
        }
        nsView.onRightClick = onRightClick
        nsView.onClick = onClick
    }
    
    private func renderDragPreview() -> NSImage {
        let content = dragPreviewContent()
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        if let nsImage = renderer.nsImage {
            return nsImage
        }
        
        // Fallback to icon if rendering fails
        return viewModel.thumbnail ?? item.icon
    }
    
    final class DraggableClickView: NSView, NSDraggingSource {
        var item: ShelfItem!
        weak var viewModel: ShelfItemViewModel?
        var getDragPreview: (() -> NSImage)?
        var onRightClick: ((NSEvent, NSView) -> Void)?
        var onClick: ((NSEvent, NSView) -> Void)?

        private var mouseDownEvent: NSEvent?
        private let dragThreshold: CGFloat = 3.0
        private var draggedURLs: [URL] = []
        private var draggedItems: [ShelfItem] = []
        private var promisedItemIDs: Set<ShelfItem.ID> = []
        private var filePromiseDelegates: [TemporaryFilePromiseDelegate] = []
        
        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(event, self)
        }
        
        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            onClick?(event, self)
        }
        
        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent = mouseDownEvent else {
                super.mouseDragged(with: event)
                return
            }
            
            let dragDistance = hypot(
                event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                event.locationInWindow.y - mouseDownEvent.locationInWindow.y
            )
            
            if dragDistance > dragThreshold {
                startDragSession(with: event)
                self.mouseDownEvent = nil
            } else {
                super.mouseDragged(with: event)
            }
        }
        
        private func startDragSession(with event: NSEvent) {
            // Prepare dragging items
            let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            let shelfItemsToRemove: [ShelfItem]

            if selectedItems.count > 1 && selectedItems.contains(where: { $0.id == item.id }) {
                shelfItemsToRemove = selectedItems
            } else {
                shelfItemsToRemove = [item]
            }

            let itemsToDrag = shelfItemsToRemove.flatMap(\.flattenedItems)

            // Store items being dragged for auto-remove feature
            draggedItems = shelfItemsToRemove
            for parent in shelfItemsToRemove where parent.flattenedItems.contains(where: \.isTemporary) {
                promisedItemIDs.insert(parent.id)
            }

            // Create dragging items for AppKit
            var draggingItems: [NSDraggingItem] = []

            for dragItem in itemsToDrag {
                if let pasteboardWriter = pasteboardWriter(for: dragItem) {
                    let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)

                    // Use the drag preview image - generated on demand
                    let image = getDragPreview?() ?? dragItem.icon
                    let imageFrame = NSRect(
                        x: 0,
                        y: 0,
                        width: image.size.width,
                        height: image.size.height
                    )
                    draggingItem.setDraggingFrame(imageFrame, contents: image)

                    draggingItems.append(draggingItem)
                }
            }

            guard !draggingItems.isEmpty else { return }

            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        private func pasteboardWriter(for item: ShelfItem) -> (any NSPasteboardWriting)? {
            if item.isTemporary,
               case .file = item.kind,
               let sourceURL = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                let fileType = UTType(filenameExtension: sourceURL.pathExtension)?.identifier
                    ?? UTType.data.identifier
                let delegate = TemporaryFilePromiseDelegate(sourceURL: sourceURL)
                delegate.onCompletion = { [weak self, weak delegate] in
                    guard let delegate else { return }
                    DispatchQueue.main.async {
                        self?.filePromiseDelegates.removeAll { $0 === delegate }
                    }
                }
                filePromiseDelegates.append(delegate)
                promisedItemIDs.insert(item.id)

                return NSFilePromiseProvider(fileType: fileType, delegate: delegate)
            }

            switch item.kind {
            case .file:
                guard let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else {
                    let fallback = NSPasteboardItem()
                    fallback.setString(item.displayName, forType: .string)
                    return fallback
                }

                // Start accessing security-scoped resource and keep it active during drag
                if url.startAccessingSecurityScopedResource() {
                    draggedURLs.append(url)
                    NSLog("🔐 Started security-scoped access for drag: \(url.path)")
                }

                return url as NSURL

            case .text(let string):
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(string, forType: .string)
                return pasteboardItem

            case .link(let url):
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .URL)
                pasteboardItem.setString(url.absoluteString, forType: .string)
                return pasteboardItem
            case .stack:
                return nil
            }
        }
        
        // MARK: - NSDraggingSource
        
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // When copyOnDrag is enabled, only allow copy operations
            if Defaults[.copyOnDrag] {
                return [.copy]
            }
            
            switch context {
            case .outsideApplication:
                return [.copy, .move]
            case .withinApplication:
                return [.copy, .move, .generic]
            @unknown default:
                return [.copy]
            }
        }
        
        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            ShelfSelectionModel.shared.beginDrag()
        }
        
        
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            ShelfSelectionModel.shared.endDrag()

            // Stop accessing security-scoped resources after drag completes
            for url in draggedURLs {
                url.stopAccessingSecurityScopedResource()
                NSLog("🔐 Stopped security-scoped access after drag: \(url.path)")
            }
            draggedURLs.removeAll()

            // Auto-remove items from shelf if enabled and drag succeeded
            if Defaults[.autoRemoveShelfItems] && !operation.isEmpty {
                // Promised files must remain available until Finder finishes
                // copying them out of the sandbox.
                for item in draggedItems where !promisedItemIDs.contains(item.id) {
                    ShelfStateViewModel.shared.remove(item)
                }
            }
            draggedItems.removeAll()
            promisedItemIDs.removeAll()
        }
        
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            return false
        }
    }
}

private final class TemporaryFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let sourceURL: URL
    var onCompletion: (() -> Void)?

    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "boringNotch.markdown-file-promise"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        super.init()
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        sourceURL.lastPathComponent
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            // copyItem never overwrites an existing destination.
            try FileManager.default.copyItem(at: sourceURL, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
        onCompletion?()
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }
}
