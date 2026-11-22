// XDRBoost, GPL-3.0. Tiny EDR trigger + gamma technique informed by
// BrightIntosh (Niklas Rousset). See THIRD_PARTY_NOTICES.md.
import AppKit
import MetalKit
import Darwin

struct GammaSnapshot: Codable {
    let display: CGDirectDisplayID
    let red: [Float]
    let green: [Float]
    let blue: [Float]
    static func capture(_ display: CGDirectDisplayID) throws -> GammaSnapshot {
        // Extended-range writes were verified with 256 entries on this Mac.
        let size: UInt32 = 256
        var red = [Float](repeating: 0, count: Int(size))
        var green = red, blue = red
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(display, size, &red, &green, &blue, &count)
        guard result == .success, count >= 2 else { throw BoostError.gammaRead }
        return GammaSnapshot(display: display, red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }
    @discardableResult func apply(_ factor: Float = 1) -> CGError {
        let r = red.map { $0 * factor }, g = green.map { $0 * factor }, b = blue.map { $0 * factor }
        return CGSetDisplayTransferByTable(display, UInt32(r.count), r, g, b)
    }
    func matches(_ original: GammaSnapshot, factor: Float = 1, tolerance: Float = 0.003) -> Bool {
        let pairs = [(red, original.red), (green, original.green), (blue, original.blue)]
        return pairs.allSatisfy { actual, base in
            actual.count == base.count && zip(actual, base).allSatisfy { abs($0 - $1 * factor) < tolerance }
        }
    }
}

enum BoostError: LocalizedError {
    case gammaRead, gammaWrite, colorConflict, recoveryUnavailable, renderStalled
    var errorDescription: String? {
        switch self {
        case .gammaRead: return "无法读取 Gamma，增强已关闭"
        case .gammaWrite: return "Gamma 写入失败，增强已关闭"
        case .colorConflict: return "色彩设置已变化，增强已关闭"
        case .recoveryUnavailable: return "恢复保护不可用，增强已关闭"
        case .renderStalled: return "EDR 渲染异常，增强已关闭"
        }
    }
}

struct RecoveryMessage: Codable {
    var command: String
    var snapshots: [GammaSnapshot]? = nil
    var display: CGDirectDisplayID? = nil
    var factors: [Float]? = nil
}

// A small, atomic prepare message is queued BEFORE each gamma write. The child
// restores only gamma values still owned by this session, even after a crash.
// Writes are nonblocking; no child can hang the UI thread.
final class GammaRecovery {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let started = ProcessInfo.processInfo.systemUptime
    private(set) var ready = false
    private var acknowledgement = Data()
    private var finished = false
    var pid: Int32 { process.processIdentifier }
    init(_ snapshots: [GammaSnapshot]) throws {
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--restore-gamma-on-eof"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        let fd = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.acknowledgement.append(bytes)
                if self.acknowledgement.starts(with: Data("READY\n".utf8)) { self.ready = true }
            }
        }
        do { try send(RecoveryMessage(command: "init", snapshots: snapshots)) }
        catch { finish(); throw error }
    }
    private func send(_ message: RecoveryMessage) throws {
        guard !finished, process.isRunning else { throw BoostError.recoveryUnavailable }
        var data = try JSONEncoder().encode(message)
        data.append(10)
        // The init message precedes any writes to the display. A partial init
        // safely aborts startup. Subsequent prepare/disarm messages fit PIPE_BUF.
        let written = data.withUnsafeBytes { raw in Darwin.write(input.fileHandleForWriting.fileDescriptor, raw.baseAddress, raw.count) }
        guard written == data.count else { throw BoostError.recoveryUnavailable }
    }
    func prepare(display: CGDirectDisplayID, previous: Float, next: Float) throws {
        guard ready else { throw BoostError.recoveryUnavailable }
        try send(RecoveryMessage(command: "prepare", display: display, factors: [previous, next]))
    }
    func checkHealth() throws {
        guard process.isRunning, ready || ProcessInfo.processInfo.systemUptime - started < 3 else {
            throw BoostError.recoveryUnavailable
        }
    }
    func finish() {
        guard !finished else { return }
        // The parent has restored its own tables or relinquished foreign ones.
        // Retire the child BEFORE EOF, synchronously without waiting. Even a
        // SIGSTOP'ed child cannot survive an immediate application exit.
        finished = true
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        input.fileHandleForWriting.closeFile()
        output.fileHandleForReading.readabilityHandler = nil
        output.fileHandleForReading.closeFile()
    }
    deinit { finish() }

    static func runHelper() -> Int32 {
        var pending = Data()
        var baselines: [GammaSnapshot] = []
        var ownedFactors: [CGDirectDisplayID: [Float]] = [:]
        while true {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            guard pending.count < 256_000 else { return 2 }
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                guard let message = try? JSONDecoder().decode(RecoveryMessage.self, from: line) else { return 2 }
                switch message.command {
                case "init":
                    baselines = message.snapshots ?? []
                    for snapshot in baselines { ownedFactors[snapshot.display] = [1] }
                    FileHandle.standardOutput.write(Data("READY\n".utf8))
                case "prepare":
                    if let display = message.display, let factors = message.factors { ownedFactors[display] = factors }
                case "disarm": return 0
                default: return 2
                }
            }
        }
        var result: Int32 = 0
        for baseline in baselines {
            guard let actual = try? GammaSnapshot.capture(baseline.display),
                  (ownedFactors[baseline.display] ?? []).contains(where: { actual.matches(baseline, factor: $0) }) else { continue }
            if baseline.apply() != .success { result = 1 }
        }
        return result
    }
}

final class EDRTriggerView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private(set) var completedFrames = 0
    private(set) var lastSuccess: TimeInterval?
    private(set) var consecutiveFailures = 0
    private(set) var renderingError: String?
    init(triggerFrame frame: NSRect) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw BoostError.renderStalled }
        self.queue = queue
        super.init(frame: frame, device: device)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        clearColor = MTLClearColorMake(1.6, 1.6, 1.6, 1)
        preferredFramesPerSecond = 3
        guard let metal = layer as? CAMetalLayer else { throw BoostError.renderStalled }
        metal.wantsExtendedDynamicRangeContent = true
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("unsupported") }
    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            consecutiveFailures += 1
            return
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.addCompletedHandler { [weak self] command in
            let success = command.status == .completed
            let error = command.error?.localizedDescription ?? "Metal command buffer did not complete"
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.completedFrames += 1
                    self.lastSuccess = ProcessInfo.processInfo.systemUptime
                    self.consecutiveFailures = 0
                    self.renderingError = nil
                } else {
                    self.consecutiveFailures += 1
                    self.renderingError = error
                }
            }
        }
        buffer.commit()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

final class TriggerWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class GammaBoost {
    struct Session {
        let baseline: GammaSnapshot
        let frame: NSRect
        let window: TriggerWindow
        var view: EDRTriggerView
        var factor: Float = 1
        var started = ProcessInfo.processInfo.systemUptime
        var repairs = 0
    }
    private(set) var sessions: [Session] = []
    private var recovery: GammaRecovery?
    var recoveryPID: Int32? { recovery?.pid }
    var isActive: Bool { !sessions.isEmpty }
    var frames: Int { sessions.reduce(0) { $0 + $1.view.completedFrames } }
    var renderingErrors: [String] { sessions.compactMap { $0.view.renderingError } }
    func matchesScreens(_ screens: [NSScreen]) -> Bool {
        sessions.count == screens.count && zip(sessions, screens).allSatisfy {
            $0.baseline.display == displayID($1) && $0.frame == $1.frame
        }
    }
    func start(screens: [NSScreen]) throws {
        stop()
        guard !screens.isEmpty else { return }
        let baselines = try screens.map { try GammaSnapshot.capture(displayID($0)) }
        recovery = try GammaRecovery(baselines)
        do {
            for (screen, baseline) in zip(screens, baselines) {
                let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1)
                let window = TriggerWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.setFrame(frame, display: false)
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
                window.animationBehavior = .none
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.hidesOnDeactivate = false
                window.isExcludedFromWindowsMenu = true
                let view = try EDRTriggerView(triggerFrame: NSRect(origin: .zero, size: frame.size))
                window.contentView = view
                sessions.append(Session(baseline: baseline, frame: screen.frame, window: window, view: view))
                window.orderFrontRegardless()
                view.draw()
            }
        } catch { stop(); throw error }
    }
    static func effectiveGain(requested: CGFloat, headroom: CGFloat) -> CGFloat {
        guard requested.isFinite, headroom.isFinite else { return 1 }
        return max(1, min(requested, headroom))
    }
    static func gammaFactor(gain: CGFloat, headroom: CGFloat, potential: CGFloat) -> Float {
        guard gain.isFinite, headroom.isFinite, potential.isFinite else { return 1 }
        let reference: CGFloat = 3.2
        let maximum = max(potential, reference + 0.01)
        let highHeadroomRolloff = 1 - min(max((headroom - reference) / (maximum - reference), 0), 1)
        // Fixed reference span avoids dividing by near-zero live headroom.
        // The curve is continuous at EDR=1 and never magnifies tiny headroom.
        let fraction = min((effectiveGain(requested: gain, headroom: headroom) - 1) / (reference - 1), 1)
        return Float(1 + 0.59 * highHeadroomRolloff * fraction)
    }
    private func assertOwnership(_ session: Session) throws {
        let actual = try GammaSnapshot.capture(session.baseline.display)
        guard actual.matches(session.baseline, factor: session.factor) else { throw BoostError.colorConflict }
    }
    private func setFactor(_ index: Int, _ factor: Float) throws {
        try assertOwnership(sessions[index])
        guard let recovery, recovery.ready else { return }
        try recovery.prepare(display: sessions[index].baseline.display, previous: sessions[index].factor, next: factor)
        let result = sessions[index].baseline.apply(factor)
        if result != .success {
            // If a failed native call nevertheless changed the table, retain
            // ownership information so stop() can still restore it.
            if let actual = try? GammaSnapshot.capture(sessions[index].baseline.display), actual.matches(sessions[index].baseline, factor: factor) {
                sessions[index].factor = factor
            }
            throw BoostError.gammaWrite
        }
        sessions[index].factor = factor
    }
    func apply(gain: CGFloat, screens: [NSScreen]) throws {
        try recovery?.checkHealth()
        guard recovery?.ready == true else { return }
        for index in sessions.indices {
            guard let screen = screens.first(where: { displayID($0) == sessions[index].baseline.display }) else { continue }
            let factor = Self.gammaFactor(gain: gain, headroom: screen.maximumExtendedDynamicRangeColorComponentValue, potential: screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            if abs(sessions[index].factor - factor) >= 0.0005 { try setFactor(index, factor) }
        }
    }
    func checkIntegrity() throws {
        try recovery?.checkHealth()
        for session in sessions { try assertOwnership(session) }
    }
    func repairStalledTriggers(now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        for index in sessions.indices {
            let session = sessions[index]
            guard now - session.started >= 5 else { continue }
            let stalled = now - (session.view.lastSuccess ?? session.started) > 4 || session.view.consecutiveFailures >= 3
            guard stalled else { continue }
            guard session.repairs < 1 else { throw BoostError.renderStalled }
            // Release the gamma boost before replacing a failed EDR source.
            try setFactor(index, 1)
            let view = try EDRTriggerView(triggerFrame: NSRect(origin: .zero, size: session.window.frame.size))
            session.view.isPaused = true
            session.window.contentView = view
            sessions[index].view = view
            sessions[index].started = ProcessInfo.processInfo.systemUptime
            sessions[index].repairs += 1
            view.draw()
        }
    }
    @discardableResult func stop() -> Bool {
        let ending = sessions
        sessions.removeAll()
        let watchdog = recovery
        recovery = nil
        var restored = true
        for session in ending {
            // An external writer owns any different table: preserve it.
            if let actual = try? GammaSnapshot.capture(session.baseline.display) {
                if actual.matches(session.baseline, factor: session.factor), session.baseline.apply() != .success { restored = false }
            } else { restored = false }
            session.view.isPaused = true
            session.window.orderOut(nil)
            session.window.contentView = nil
        }
        watchdog?.finish()
        return restored
    }
    deinit { stop() }
}
