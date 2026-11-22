// Regression diagnostics. Run --self-test after quitting the normal application.
import AppKit
import Darwin

final class BoostDiagnostics {
    private let app: AppDelegate
    private var results: [(String, Bool)] = []
    private var baselines: [GammaSnapshot] = []
    private let storedGain = UserDefaults.standard.object(forKey: "gain")
    init(_ app: AppDelegate) { self.app = app }
    private func record(_ name: String, _ passed: Bool) {
        results.append((name, passed))
        print("\(name) \(passed ? "PASS" : "FAIL")")
        fflush(stdout)
    }
    private func later(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
    func run() {
        let low = GammaBoost.gammaFactor(gain: 1.25, headroom: 1.010, potential: 16)
        let high = GammaBoost.gammaFactor(gain: 1.25, headroom: 1.011, potential: 16)
        record("CONTINUOUS_CURVE", abs(high - low) < 0.001 && high < 1.01)
        record("REFERENCE_MAX", abs(GammaBoost.gammaFactor(gain: 3.2, headroom: 3.2, potential: 16) - 1.59) < 0.001)
        app.gain = 3.2
        app.updateSliderRange()
        record("USER_TARGET_RETAINED", app.gain == 3.2 && GammaBoost.effectiveGain(requested: app.gain, headroom: 1.02) == 1.02)
        app.gain = 1.1
        app.enabled = true
        app.reconcile()
        baselines = app.boost.sessions.map { $0.baseline }
        later(4) { [self] in primaryChecks() }
    }
    private func primaryChecks() {
        let sessions = app.boost.sessions
        let ids = sessions.map { $0.window.windowNumber }
        app.reconcile()
        app.thermalChanged()
        app.reconcile()
        record("IDEMPOTENT_RECONCILE", !ids.isEmpty && app.boost.sessions.map { $0.window.windowNumber } == ids)
        let tiny = !sessions.isEmpty && sessions.allSatisfy { $0.window.frame.width <= 1 && $0.view.drawableSize == CGSize(width: 1, height: 1) && $0.view.layer?.compositingFilter == nil }
        record("TINY_EDR_TRIGGER", tiny && app.boost.frames > 0 && app.boost.renderingErrors.isEmpty)
        let limit = app.slider.maxValue
        var readback = app.slider.isEnabled
        for gain in [1.0, min(2.5, limit), limit, 1.1] {
            app.slider.doubleValue = gain
            readback = app.slider.sendAction(app.slider.action, to: app.slider.target) && readback
            readback = readback && abs(Double(app.gain) - gain) < 0.001
            for session in app.boost.sessions {
                readback = readback && ((try? GammaSnapshot.capture(session.baseline.display).matches(session.baseline, factor: session.factor)) ?? false)
            }
        }
        record("SLIDER_GAMMA_READBACK", readback && app.boost.sessions.contains { $0.factor > 1.001 })
        let oldView = app.boost.sessions.first?.view
        do {
            try app.boost.repairStalledTriggers(now: ProcessInfo.processInfo.systemUptime + 6)
            record("RENDER_STALL_REPAIR", oldView != nil && app.boost.sessions.first?.view !== oldView)
        } catch { record("RENDER_STALL_REPAIR", false) }
        later(1) { [self] in
            record("REPAIRED_RENDERING", app.boost.frames > 0)
            colorConflictCheck()
        }
    }
    private func colorConflictCheck() {
        guard let original = baselines.first else { record("COLOR_CONFLICT_PRESERVED", false); finish(); return }
        _ = original.apply(0.97) // Simulate a different app changing gamma.
        let foreign = try? GammaSnapshot.capture(original.display)
        app.maintenance()
        let after = try? GammaSnapshot.capture(original.display)
        record("COLOR_CONFLICT_PRESERVED", !app.enabled && !app.boost.isActive && foreign != nil && (after?.matches(foreign!) ?? false))
        _ = original.apply()
        wakeCheck()
    }
    private func wakeCheck() {
        app.enabled = true
        app.lastError = nil
        app.reconcile()
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        record("DISPLAY_SLEEP_GATE", !app.boost.isActive && app.sleeping)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        later(1) { [self] in
            let ids = app.boost.sessions.map { $0.window.windowNumber }
            app.reconcile()
            record("WAKE_DEBOUNCE", !ids.isEmpty && ids == app.boost.sessions.map { $0.window.windowNumber })
            later(1) { [self] in watchdogFailureCheck() }
        }
    }
    private func watchdogFailureCheck() {
        guard let pid = app.boost.recoveryPID else { record("WATCHDOG_DEATH", false); finish(); return }
        kill(pid, SIGKILL)
        later(0.4) { [self] in
            app.maintenance()
            record("WATCHDOG_DEATH", !app.enabled && !app.boost.isActive)
            app.enabled = true
            app.lastError = nil
            app.reconcile()
            later(1) { [self] in watchdogHangCheck() }
        }
    }
    private func watchdogHangCheck() {
        guard let pid = app.boost.recoveryPID else { record("NONBLOCKING_STOP", false); finish(); return }
        kill(pid, SIGSTOP)
        let start = ProcessInfo.processInfo.systemUptime
        app.reset()
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        record("NONBLOCKING_STOP", elapsed < 0.25 && !app.boost.isActive)
        later(1.3) { [self] in
            record("HUNG_CHILD_REAPED", kill(pid, 0) != 0)
            finish()
        }
    }
    private func finish() {
        app.reset()
        var restored = !baselines.isEmpty
        for baseline in baselines {
            restored = restored && ((try? GammaSnapshot.capture(baseline.display).matches(baseline)) ?? false)
            _ = baseline.apply() // Ensure the diagnostic's simulated color edit is undone.
        }
        record("FINAL_GAMMA_RESTORED", restored)
        UserDefaults.standard.set(storedGain, forKey: "gain")
        let passed = results.allSatisfy { $0.1 }
        verificationStatus = passed ? 0 : 1
        print("REGRESSION_SUITE \(passed ? "PASS" : "FAIL") checks=\(results.count)")
        fflush(stdout)
        NSApp.terminate(nil)
    }
}
