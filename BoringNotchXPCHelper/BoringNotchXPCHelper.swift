//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import AppKit
import ApplicationServices
import IOKit

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {

    private weak var connection: NSXPCConnection?

    private let lunarStateQueue = DispatchQueue(label: "BoringNotchXPCHelper.lunar.state")
    private let lunarExecutableURL = URL(fileURLWithPath: "/Applications/Lunar.app/Contents/MacOS/Lunar")
    private var lunarProcess: Process?
    private var lunarPipeHandler: JSONLinesPipeHandler?
    private var lunarStreamTask: Task<Void, Never>?
    private var lunarListener: BoringNotchXPCHelperLunarListener?
    private let processQueue = DispatchQueue(label: "Nodebay.approved-processes", attributes: .concurrent)
    private let processStateQueue = DispatchQueue(label: "Nodebay.approved-processes.state")
    private var approvedProcesses: [String: Process] = [:]
    private var cancelledProcessIDs: Set<String> = []

    init(connection: NSXPCConnection) {
        self.connection = connection
        super.init()
    }

    override init() {
        super.init()
    }

    deinit {
        var processToTerminate: Process?
        var taskToCancel: Task<Void, Never>?
        var pipeHandlerToClose: JSONLinesPipeHandler?

        lunarStateQueue.sync {
            processToTerminate = self.lunarProcess
            self.lunarProcess = nil

            taskToCancel = self.lunarStreamTask
            self.lunarStreamTask = nil

            pipeHandlerToClose = self.lunarPipeHandler
            self.lunarPipeHandler = nil

            self.lunarListener = nil
        }

        taskToCancel?.cancel()
        if let p = processToTerminate, p.isRunning { p.terminate() }
        if let ph = pipeHandlerToClose {
            Task { await ph.close() }
        }
        processStateQueue.sync {
            approvedProcesses.values.forEach { if $0.isRunning { $0.terminate() } }
            approvedProcesses.removeAll()
        }
    }
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    private func brightnessDisplayID() -> CGDirectDisplayID {
        let mainDisplayID = CGMainDisplayID()
        var tmp: Float = 0

        if displayServicesGetBrightness(displayID: mainDisplayID, out: &tmp) || ioServiceFor(displayID: mainDisplayID) != nil {
            return mainDisplayID
        }

        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        let allocated = Int(count)
        var ids = [CGDirectDisplayID](repeating: 0, count: allocated)
        CGGetOnlineDisplayList(count, &ids, &count)
        for id in ids {
            if CGDisplayIsBuiltin(id) != 0 {
                return id
            }
        }

        return mainDisplayID
    }

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        let displayID = brightnessDisplayID()
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: displayID, out: &b) || ioServiceFor(displayID: displayID) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        let displayID = brightnessDisplayID()
        var b: Float = 0
        if displayServicesGetBrightness(displayID: displayID, out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        let displayID = brightnessDisplayID()
        if displayServicesSetBrightness(displayID: displayID, value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }
    
    @objc func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void) {
        let displayID = brightnessDisplayID()
        if displayServicesSetBrightnessSmooth(displayID: displayID, value: value) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            var ioCurrent: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &ioCurrent) == kIOReturnSuccess {
                let target = max(0, min(1, ioCurrent + value))
                let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, target) == kIOReturnSuccess
                IOObjectRelease(io)
                reply(ok)
                return
            }
            IOObjectRelease(io)
        }
        reply(false)
    }

    // MARK: - Lunar Events

    @objc func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void) {
        let id = brightnessDisplayID()
        reply(NSNumber(value: id))
    }

    @objc func isLunarAvailable(with reply: @escaping (Bool) -> Void) {
        reply(FileManager.default.isExecutableFile(atPath: lunarExecutableURL.path))
    }

    @objc func startLunarEventStream(with reply: @escaping (Bool) -> Void) {
        lunarStateQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }

            if let lunarProcess = self.lunarProcess, lunarProcess.isRunning {
                reply(true)
                return
            }

            guard FileManager.default.isExecutableFile(atPath: self.lunarExecutableURL.path) else {
                reply(false)
                return
            }

            guard let connection = self.connection else {
                reply(false)
                return
            }

            let listenerProxy = connection.remoteObjectProxyWithErrorHandler { _ in
                self.stopLunarEventStream()
            } as? BoringNotchXPCHelperLunarListener

            guard let listenerProxy else {
                reply(false)
                return
            }

            let process = Process()
            process.executableURL = self.lunarExecutableURL
            process.arguments = ["@", "listen", "--only-user-adjustments", "-j"]

            let pipeHandler = JSONLinesPipeHandler(decoder: JSONDecoder())
            process.standardOutput = pipeHandler.getPipe()
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { [weak self] _ in
                self?.stopLunarEventStream(reason: "Lunar stream ended")
            }

            do {
                try process.run()
            } catch {
                reply(false)
                return
            }

            self.lunarProcess = process
            self.lunarPipeHandler = pipeHandler
            self.lunarListener = listenerProxy

            let currentPipeHandler = pipeHandler
            self.lunarStreamTask = Task { [weak self] in
                await self?.readLunarEvents(pipeHandler: currentPipeHandler)
            }

            reply(true)
        }
    }

    @objc func stopLunarEventStream() {
        stopLunarEventStream(reason: nil)
    }

    private func stopLunarEventStream(reason: String?) {
        lunarStateQueue.async { [weak self] in
            guard let self else { return }

            self.lunarStreamTask?.cancel()
            self.lunarStreamTask = nil

            if let lunarProcess = self.lunarProcess, lunarProcess.isRunning {
                lunarProcess.terminate()
            }

            self.lunarProcess = nil

            if let pipeHandler = self.lunarPipeHandler {
                Task { await pipeHandler.close() }
            }

            self.lunarPipeHandler = nil

            if let reason {
                self.lunarListener?.lunarStreamDidStop(reason)
            }

            self.lunarListener = nil
        }
    }

    private func readLunarEvents(pipeHandler: JSONLinesPipeHandler) async {
        await pipeHandler.readJSONLines(as: LunarBrightnessEvent.self) { [weak self] event in
            self?.emitLunarEvent(event)
        }
    }

    private func emitLunarEvent(_ event: LunarBrightnessEvent) {
        let payload = BNLunarBrightnessEvent(
            brightness: event.brightness,
            display: event.display
        )
        lunarStateQueue.async { [weak self] in
            self?.lunarListener?.lunarEventDidUpdate(payload)
        }
    }

    // MARK: - Lunar OSD preference (hideOSD)

    private static let lunarBundleID = "fyi.lunar.Lunar"
    private static let lunarHideOSDKey = "hideOSD"

    @objc func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void) {
        let appID = Self.lunarBundleID as CFString
        let key = Self.lunarHideOSDKey as CFString
        let value = hide as CFBoolean
        NSLog("Hide OSD in Lunar: \(hide)")
        CFPreferencesSetValue(key, value, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let ok = CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        reply(ok)
    }

    // MARK: - Isolated Nodebay processing engines

    @objc func runApprovedProcess(
        _ jobID: String,
        engine: String,
        executablePath: String,
        arguments: [String],
        timeout: Double,
        maximumLogBytes: Int,
        with reply: @escaping (NSNumber, String, String, String?) -> Void
    ) {
        guard jobID.utf8.count <= 128,
              arguments.count <= 256,
              arguments.allSatisfy({ $0.utf8.count <= 16_384 && !$0.contains("\0") }),
              let executableURL = approvedExecutable(engine: engine, path: executablePath),
              validateArguments(engine: engine, arguments: arguments) else {
            reply(-1, "", "", "Nodebay rejected an unapproved engine request.")
            return
        }

        processQueue.async { [weak self] in
            guard let self else { return }
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let stdoutBuffer = ProcessOutputBuffer(limit: maximumLogBytes)
            let stderrBuffer = ProcessOutputBuffer(limit: maximumLogBytes)
            let progressParser = engine == "yt-dlp" ? ApprovedProcessProgressParser(jobID: jobID) : nil
            let progressListener = self.connection?.remoteObjectProxy as? BoringNotchXPCHelperLunarListener
            let finishLock = NSLock()
            var didFinish = false

            func finish(code: Int32, error: String? = nil) {
                finishLock.lock()
                guard !didFinish else { finishLock.unlock(); return }
                didFinish = true
                finishLock.unlock()
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
                _ = self.processStateQueue.sync { self.approvedProcesses.removeValue(forKey: jobID) }
                reply(NSNumber(value: code), stdoutBuffer.string, stderrBuffer.string, error)
            }

            process.executableURL = executableURL
            process.arguments = arguments
            if engine == "stl-repair" {
                let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let script = app.appendingPathComponent("Contents/Resources/stl_repair.py")
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                let flags = arguments == ["--version"] ? arguments : [
                    "--background", "--factory-startup", "--disable-autoexec", "--offline-mode", "--threads", "2",
                    "--python-exit-code", "7", "--python", script.path, "--", "--mode", arguments[0], "--job", arguments[1]
                ]
                process.arguments = ["-p", "(version 1) (allow default) (deny network*)", executableURL.path] + flags
            }
            process.standardOutput = stdout
            process.standardError = stderr
            var environment = ProcessInfo.processInfo.environment
            if engine == "stl-repair" {
                // Do not load caller-selected Python modules or Blender scripts.
                environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "PYTHONNOUSERSITE": "1"]
            }
            if engine == "markitdown" {
                environment["MARKITDOWN_LOCAL_ONLY"] = "1"
                environment["PYTHONNOUSERSITE"] = "1"
                environment["NO_PROXY"] = "*"
                environment["no_proxy"] = "*"
                for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
                    environment.removeValue(forKey: key)
                }
            }
            process.environment = environment
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                stdoutBuffer.append(data)
                progressParser?.append(data) { event in progressListener?.approvedProcessDidUpdate(event) }
            }
            stderr.fileHandleForReading.readabilityHandler = { stderrBuffer.append($0.availableData) }
            process.terminationHandler = { finished in finish(code: finished.terminationStatus) }

            do {
                // Serialize launch with cancellation so cancellation arriving
                // before Process.run cannot be lost while work is queued.
                try self.processStateQueue.sync {
                    guard self.cancelledProcessIDs.remove(jobID) == nil else { throw CancellationError() }
                    self.approvedProcesses[jobID] = process
                    try process.run()
                }
            } catch {
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                finish(code: -1, error: error.localizedDescription)
                return
            }

            let boundedTimeout = min(max(timeout, 1), 7_200)
            self.processQueue.asyncAfter(deadline: .now() + boundedTimeout) {
                if process.isRunning {
                    process.terminate()
                    if engine == "stl-repair" {
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                    finish(code: -2, error: "The engine exceeded its time limit.")
                }
            }
        }
    }

    @objc func firstAvailableApprovedExecutable(
        _ engine: String,
        candidatePaths: [String],
        with reply: @escaping (String?) -> Void
    ) {
        guard candidatePaths.count <= 4,
              candidatePaths.allSatisfy({ $0.hasPrefix("/") && $0.utf8.count <= 1_024 }) else {
            reply(nil)
            return
        }
        reply(candidatePaths.lazy.compactMap { self.approvedExecutable(engine: engine, path: $0)?.path }.first)
    }

    @objc func cancelApprovedProcess(_ jobID: String) {
        processStateQueue.sync {
            if let process = approvedProcesses[jobID], process.isRunning {
                process.terminate()
                if process.arguments?.contains("(version 1) (allow default) (deny network*)") == true {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            } else {
                if cancelledProcessIDs.count >= 512 { cancelledProcessIDs.removeAll() }
                cancelledProcessIDs.insert(jobID)
            }
        }
    }

    // MARK: - Browser media bridge

    private static let browserBridgeExtensionID = "moppfhahpgimiknnknkmchmjljfhhdaf"
    private static let browserBridgeHostName = "com.nodebay.browser_bridge"

    @objc func installBrowserBridgeManifest(
        _ nativeHostPath: String,
        extensionID: String,
        with reply: @escaping (Bool, String?) -> Void
    ) {
        guard extensionID == Self.browserBridgeExtensionID,
              let executable = validatedBrowserBridgeExecutable(nativeHostPath)
        else {
            reply(false, "The bundled browser bridge failed validation.")
            return
        }

        let manifest: [String: Any] = [
            "name": Self.browserBridgeHostName,
            "description": "Nodebay local browser media bridge",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(Self.browserBridgeExtensionID)/"],
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            let directory = browserBridgeManifestURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: browserBridgeManifestURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: browserBridgeManifestURL.path)
            reply(true, nil)
        } catch {
            reply(false, "Could not install the Chrome native host manifest: \(error.localizedDescription)")
        }
    }

    @objc func removeBrowserBridgeManifest(with reply: @escaping (Bool, String?) -> Void) {
        do {
            if FileManager.default.fileExists(atPath: browserBridgeManifestURL.path) {
                try FileManager.default.removeItem(at: browserBridgeManifestURL)
            }
            reply(true, nil)
        } catch {
            reply(false, "Could not remove the Chrome native host manifest: \(error.localizedDescription)")
        }
    }

    @objc func browserBridgeManifestStatus(with reply: @escaping (Bool, String?) -> Void) {
        guard let data = try? Data(contentsOf: browserBridgeManifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["name"] as? String == Self.browserBridgeHostName,
              let path = manifest["path"] as? String,
              validatedBrowserBridgeExecutable(path) != nil,
              let origins = manifest["allowed_origins"] as? [String],
              origins == ["chrome-extension://\(Self.browserBridgeExtensionID)/"]
        else {
            reply(false, "Chrome native host is not installed.")
            return
        }
        reply(true, nil)
    }

    private var browserBridgeManifestURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
            .appending(path: "\(Self.browserBridgeHostName).json")
    }

    private func validatedBrowserBridgeExecutable(_ path: String) -> URL? {
        guard path.hasPrefix("/"), path.utf8.count <= 2_048 else { return nil }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        let suffix = ".app/Contents/Resources/BrowserBridge/native/nodebay-browser-bridge"
        guard url.path.contains(suffix),
              url.lastPathComponent == "nodebay-browser-bridge",
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url
    }

    private func approvedExecutable(engine: String, path: String) -> URL? {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        switch engine {
        case "markitdown":
            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let allowedRoot = appURL.appending(path: "Contents/Resources/markitdown-runtime").standardizedFileURL.path + "/"
            return url.path.hasPrefix(allowedRoot) && url.lastPathComponent == "markitdown-local" ? url : nil
        case "yt-dlp":
            return ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"].contains(url.path) ? url : nil
        case "imageoptim":
            return url.path == "/Applications/ImageOptim.app/Contents/MacOS/ImageOptim" ? url : nil
        case "ffmpeg":
            return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].contains(url.path) ? url : nil
        case "stl-repair":
            return url.path == "/Applications/Blender.app/Contents/MacOS/Blender" ? url : nil
        default:
            return nil
        }
    }

    private func validateArguments(engine: String, arguments: [String]) -> Bool {
        switch engine {
        case "markitdown":
            return arguments == ["--nodebay-version"] || (arguments.count == 4 && arguments[0] == "--input" && arguments[2] == "--output"
                && arguments[1].hasPrefix("/") && arguments[3].hasPrefix("/")
            )
        case "imageoptim":
            return arguments.count == 1 && arguments[0].hasPrefix("/")
        case "yt-dlp":
            return arguments == ["--version"] || arguments.prefix(4) == ["--ignore-config", "--no-config-locations", "--no-plugin-dirs", "--no-cookies-from-browser"]
        case "ffmpeg":
            return !arguments.isEmpty
        case "stl-repair":
            if arguments == ["--version"] { return true }
            guard arguments.count == 2, ["safe", "thorough", "inspect"].contains(arguments[0]) else { return false }
            let job = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Containers/theboringteam.boringnotch/Data/Library/Application Support/Nodebay/STLJobs")
            guard job.deletingLastPathComponent() == root,
                  job.resolvingSymlinksInPath() == job,
                  UUID(uuidString: job.lastPathComponent) != nil,
                  let input = try? job.appendingPathComponent("input.stl").resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  input.isRegularFile == true, input.isSymbolicLink != true,
                  let size = input.fileSize, size > 0, size <= 32 * 1024 * 1024 else { return false }
            return !FileManager.default.fileExists(atPath: job.appendingPathComponent("output.stl").path)
                && !FileManager.default.fileExists(atPath: job.appendingPathComponent("report.json").path)
        default:
            return false
        }
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }
    
    private func displayServicesSetBrightnessSmooth(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightnessSmooth") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) { self.limit = min(max(limit, 0), 1_048_576) }

    func append(_ value: Data) {
        guard !value.isEmpty, limit > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = limit - data.count
        if remaining > 0 { data.append(value.prefix(remaining)) }
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class ApprovedProcessProgressParser: @unchecked Sendable {
    private let jobID: String
    private let lock = NSLock()
    private var pending = Data()
    private var lastEmission = Date.distantPast

    init(jobID: String) { self.jobID = jobID }

    func append(_ data: Data, emit: (BNApprovedProcessProgressEvent) -> Void) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending.prefix(upTo: newline)
            pending.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8), line.hasPrefix("nodebay-progress:") else { continue }
            let now = Date()
            guard now.timeIntervalSince(lastEmission) >= 0.25 || line.contains("100%") else { continue }
            lastEmission = now
            let values = line.dropFirst("nodebay-progress:".count).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard values.count == 5 else { continue }
            let percent = Double(values[0].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)).map { $0 / 100 } ?? -1
            emit(BNApprovedProcessProgressEvent(
                jobID: jobID, stage: "downloading", percentage: percent,
                downloadedBytes: Int64(values[1]) ?? -1, totalBytes: Int64(values[2]) ?? -1,
                speed: Double(values[3]) ?? -1, eta: Double(values[4]) ?? -1
            ))
        }
    }
}

// MARK: - Lunar Parsing

private struct LunarBrightnessEvent: Decodable {
    let brightness: Double
    let display: Int

    init(from decoder: NSCoder) {
        display = decoder.decodeInteger(forKey: "display")
        brightness = decoder.decodeDouble(forKey: "brightness")
    }
}

private actor JSONLinesPipeHandler {
    nonisolated let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        let pipe = Pipe()
        self.pipe = pipe
        self.fileHandle = pipe.fileHandleForReading
        self.decoder = decoder
    }

    nonisolated func getPipe() -> Pipe {
        return pipe
    }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) -> Void) async {
        do {
            try await processLines(as: type) { decodedObject in
                onLine(decodedObject)
            }
        } catch {
            // Ignore stream errors to keep the helper lightweight.
        }
    }

    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }

            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)

                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if !line.isEmpty {
                        processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }

    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) -> Void) {
        guard let data = line.data(using: .utf8) else { return }
        if let decodedObject = try? decoder.decode(T.self, from: data) {
            onLine(decodedObject)
        }
    }

    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }

    func close() async {
        do {
            fileHandle.readabilityHandler = nil

            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            // Ignore close errors.
        }
    }
}
