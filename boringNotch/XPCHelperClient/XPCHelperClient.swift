import Foundation
import Cocoa
@preconcurrency import AsyncXPCConnection

final class XPCHelperClient: NSObject, @unchecked Sendable {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    private var lunarListener: BoringNotchXPCHelperLunarListener?
    private var hasLunarListener: Bool = false
    private let progressLock = NSLock()
    private var progressHandlers: [String: @Sendable (MediaDownloadProgress) -> Void] = [:]
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService(needsListener: Bool = false) -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService, hasLunarListener {
            return existing
        }

        if let connection {
            connection.invalidate()
            self.connection = nil
            self.remoteService = nil
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)

        let listenerInterface = makeLunarListenerInterface()
        conn.exportedInterface = listenerInterface
        conn.exportedObject = self
        hasLunarListener = true
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
                self?.hasLunarListener = false
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
                self?.hasLunarListener = false
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol>? {
        remoteService
    }

    private func makeLunarListenerInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any BoringNotchXPCHelperLunarListener).self)
        interface.setClasses(
            NSSet(array: [BNLunarBrightnessEvent.self]) as! Set<AnyHashable>,
            for: #selector(BoringNotchXPCHelperLunarListener.lunarEventDidUpdate(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        interface.setClasses(
            NSSet(array: [BNApprovedProcessProgressEvent.self]) as! Set<AnyHashable>,
            for: #selector(BoringNotchXPCHelperLunarListener.approvedProcessDidUpdate(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        return interface
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }

    nonisolated func displayIDForBrightness() async -> CGDirectDisplayID? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.displayIDForBrightness(with: { value in
                    continuation.resume(returning: value)
                })
            }
            guard let num = result else { return nil }
            return CGDirectDisplayID(num.uint32Value)
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    nonisolated func adjustScreenBrightness(by value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.adjustScreenBrightness(by: value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    // MARK: - Lunar Events

    nonisolated func isLunarAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isLunarAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func startLunarEventStream(listener: any BoringNotchXPCHelperLunarListener & Sendable) async -> Bool {
        await MainActor.run {
            lunarListener = listener
        }
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            return try await service.withContinuation { service, continuation in
                service.startLunarEventStream { started in
                    continuation.resume(returning: started)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func stopLunarEventStream() async {
        do {
            let service = await MainActor.run {
                ensureRemoteService(needsListener: true)
            }
            try await service.withService { service in
                service.stopLunarEventStream()
            }
        } catch {
            return
        }
    }

    nonisolated func setLunarOSDHidden(_ hide: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setLunarOSDHidden(hide) { ok in
                    continuation.resume(returning: ok)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func runApprovedProcess(
        engine: String,
        executable: URL,
        arguments: [String],
        timeout: Duration,
        maximumLogBytes: Int,
        progress: (@Sendable (MediaDownloadProgress) -> Void)? = nil
    ) async throws -> ProcessResult {
        let jobID = UUID().uuidString
        if let progress {
            progressLock.withLock { progressHandlers[jobID] = progress }
        }
        defer {
            progressLock.withLock { progressHandlers[jobID] = nil }
        }
        let seconds = timeout.components.seconds > 0 ? Double(timeout.components.seconds) : 1
        return try await withTaskCancellationHandler {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.runApprovedProcess(
                    jobID,
                    engine: engine,
                    executablePath: executable.path,
                    arguments: arguments,
                    timeout: seconds,
                    maximumLogBytes: maximumLogBytes
                ) { code, output, errorOutput, launchError in
                    if let launchError {
                        continuation.resume(throwing: SafeProcessError.launchFailed(launchError))
                    } else if code.int32Value == -2 {
                        continuation.resume(throwing: SafeProcessError.timedOut)
                    } else {
                        continuation.resume(returning: ProcessResult(
                            exitCode: code.int32Value,
                            standardOutput: output,
                            standardError: errorOutput
                        ))
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                guard let self else { return }
                let service = await MainActor.run { self.ensureRemoteService() }
                try? await service.withService { $0.cancelApprovedProcess(jobID) }
            }
        }
    }

    @objc nonisolated func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent) {
        lunarListener?.lunarEventDidUpdate(event)
    }

    @objc nonisolated func lunarStreamDidStop(_ reason: String?) {
        lunarListener?.lunarStreamDidStop(reason)
    }

    @objc nonisolated func approvedProcessDidUpdate(_ event: BNApprovedProcessProgressEvent) {
        let handler = progressLock.withLock { progressHandlers[event.jobID] }
        handler?(MediaDownloadProgress(
            stage: event.stage == "processing" ? .processing : .downloading,
            percentage: event.percentage >= 0 ? min(1, max(0, event.percentage)) : nil,
            downloadedBytes: event.downloadedBytes >= 0 ? event.downloadedBytes : nil,
            totalBytes: event.totalBytes >= 0 ? event.totalBytes : nil,
            speed: event.speed >= 0 ? event.speed : nil,
            eta: event.eta >= 0 ? event.eta : nil
        ))
    }

    nonisolated func firstAvailableApprovedExecutable(
        engine: String,
        candidates: [URL]
    ) async -> URL? {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let path: String? = try await service.withContinuation { service, continuation in
                service.firstAvailableApprovedExecutable(
                    engine,
                    candidatePaths: candidates.map(\.path)
                ) { path in
                    continuation.resume(returning: path)
                }
            }
            return path.map { URL(fileURLWithPath: $0) }
        } catch {
            return nil
        }
    }

    nonisolated func installBrowserBridgeManifest(
        nativeHostPath: String,
        extensionID: String
    ) async -> (success: Bool, message: String?) {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.installBrowserBridgeManifest(nativeHostPath, extensionID: extensionID) { success, message in
                    continuation.resume(returning: (success, message))
                }
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    nonisolated func removeBrowserBridgeManifest() async -> (success: Bool, message: String?) {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.removeBrowserBridgeManifest { success, message in
                    continuation.resume(returning: (success, message))
                }
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    nonisolated func browserBridgeManifestStatus() async -> (installed: Bool, message: String?) {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.browserBridgeManifestStatus { installed, message in
                    continuation.resume(returning: (installed, message))
                }
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
