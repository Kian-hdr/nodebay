//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import UniformTypeIdentifiers

final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?


    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false

    private let notchRegion: () -> CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: @escaping () -> CGRect) {
        self.notchRegion = notchRegion
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        guard let items = dragPasteboard.pasteboardItems, !items.isEmpty else { return false }
        return items.allSatisfy { item in
            item.types.contains { validTypes.contains($0) }
        }
    }

    func startMonitoring() {
        stopMonitoring()

        // Track pasteboard to detect content drag
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self = self else { return }
            guard self.isDragging else { return }

            // Finder and browsers can populate the drag pasteboard before or
            // after the first global drag event. Inspect the current types on
            // every move instead of relying on changeCount timing.
            if !self.isContentDragging && self.hasValidDragContent() {
                self.isContentDragging = true
            }

            // Only process position when content is being dragged
            if self.isContentDragging {
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
                // Track notch region entry/exit
                let containsMouse = self.notchRegion().contains(mouseLocation)
                if containsMouse && !self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = true
                    self.onDragEntersNotchRegion?()
                } else if !containsMouse && self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = false
                    self.onDragExitsNotchRegion?()
                }
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }
            
            if self.hasEnteredNotchRegion { self.onDragExitsNotchRegion?() }
            self.isDragging = false
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.pasteboardChangeCount = -1
        }
    }

    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}

/// Owns one dynamic edge detector per stable display identifier. The real drop
/// remains handled by SwiftUI/AppKit on the opened notch window.
@MainActor
final class NotchDragRoutingCoordinator {
    struct Target {
        let displayUUID: String
        let region: () -> CGRect
        let entered: () -> Void
        let exited: () -> Void
    }

    private var detectors: [String: DragDetector] = [:]

    func configure(_ targets: [Target]) {
        stop()
        for target in targets {
            let detector = DragDetector(notchRegion: target.region)
            detector.onDragEntersNotchRegion = target.entered
            detector.onDragExitsNotchRegion = target.exited
            detectors[target.displayUUID] = detector
            detector.startMonitoring()
        }
    }

    func stop() {
        detectors.values.forEach { $0.stopMonitoring() }
        detectors.removeAll()
    }
}

/// Handles Command-V only when Nodebay explicitly confirms that the pointer is
/// inside an open notch. The explicit-paste handler owns clipboard routing.
final class NotchPasteShortcutMonitor {
    static let shared = NotchPasteShortcutMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shouldHandle: (() -> Bool)?
    private var handler: (() -> Bool)?

    func start(shouldHandle: @escaping () -> Bool, handler: @escaping () -> Bool) {
        stop()
        self.shouldHandle = shouldHandle
        self.handler = handler
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<NotchPasteShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = monitor.eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown,
                      event.getIntegerValueField(.keyboardEventKeycode) == 9,
                      event.flags.contains(.maskCommand),
                      !event.flags.contains(.maskAlternate),
                      !event.flags.contains(.maskControl),
                      !event.flags.contains(.maskShift),
                      event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                      monitor.shouldHandle?() == true else {
                    return Unmanaged.passUnretained(event)
                }
                guard monitor.handler?() == true else { return Unmanaged.passUnretained(event) }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil; eventTap = nil; shouldHandle = nil; handler = nil
    }
}
