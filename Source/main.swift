// XDRBoost — GPL-3.0. See LICENSE and THIRD_PARTY_NOTICES.md.
import AppKit
import MetalKit
import Darwin

func modelIdentifier() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var bytes = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &bytes, &size, nil, 0)
    return String(cString: bytes)
}
func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

var verificationStatus: Int32 = 0

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    let boost = GammaBoost()
    var updating = false
    var enabled = false
    var systemSleeping = false
    var displaySleeping = false
    var sessionInactive = false
    var sleeping: Bool { systemSleeping || displaySleeping || sessionInactive }
    var resumeWork: DispatchWorkItem?
    var diagnostic: BoostDiagnostics?
    var gain: CGFloat = 1.25
    var timer: Timer?
    let popover = NSPopover()
    var toggleItem: NSButton!
    var infoItem: NSTextField!
    var gainLabel: NSTextField!
    var slider: NSSlider!
    var workspaceObservers: [NSObjectProtocol] = []
    var selfTesting = CommandLine.arguments.contains("--self-test")
    var lastError: String?

    var supportedScreens: [NSScreen] {
        NSScreen.screens.filter { CGDisplayIsBuiltin(displayID($0)) != 0 && $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent duplicate controls and competing Gamma sessions.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.XDRBoost")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            if selfTesting {
                verificationStatus = 2
                fputs("请先退出正在运行的 XDRBoost，再执行自测。\n", stderr)
            }
            NSApp.terminate(nil); return
        }
        let saved = UserDefaults.standard.double(forKey: "gain")
        gain = saved.isFinite && saved >= 1 ? min(CGFloat(saved), supportedScreens.map { $0.maximumPotentialExtendedDynamicRangeColorComponentValue }.min() ?? 1.25) : 1.25
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "XDR 亮度增强")
        status.button?.toolTip = "XDR 亮度增强"
        status.button?.target = self
        status.button?.action = #selector(showControls)
        let controller = NSViewController()
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 216))
        controller.view = panel
        func label(_ text: String, y: CGFloat, size: CGFloat = 12) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: size)
            field.frame = NSRect(x: 20, y: y, width: 280, height: 20)
            panel.addSubview(field)
            return field
        }
        func button(_ text: String, action: Selector, y: CGFloat) -> NSButton {
            let button = NSButton(title: text, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: 18, y: y, width: 284, height: 28)
            panel.addSubview(button)
            return button
        }
        _ = label("XDR 亮度增强", y: 182, size: 17)
        toggleItem = button("开启额外亮度", action: #selector(toggle), y: 142)
        gainLabel = label("", y: 114)
        slider = NSSlider(value: Double(gain), minValue: 1, maxValue: Double(max(gain, 1.25)), target: self, action: #selector(slide(_:)))
        slider.frame = NSRect(x: 20, y: 84, width: 280, height: 24)
        slider.isContinuous = true
        slider.isEnabled = true
        slider.setAccessibilityLabel("额外亮度倍率")
        panel.addSubview(slider)
        infoItem = label("", y: 56)
        let quit = button("退出", action: #selector(quit), y: 16)
        quit.toolTip = "退出并恢复正常亮度"
        popover.contentViewController = controller
        popover.contentSize = panel.frame.size
        popover.behavior = .transient
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ change: @escaping (AppDelegate) -> Void) {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                change(self)
                self.environmentChanged()
            })
        }
        observe(NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(NSWorkspace.didWakeNotification) { $0.systemSleeping = false }
        observe(NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false }
        observe(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.maintenance() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
        if selfTesting {
            diagnostic = BoostDiagnostics(self)
            diagnostic?.run()
        }
        if CommandLine.arguments.contains("--crash-test-child") {
            gain = 1.1; enabled = true; reconcile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
                refresh()
                print("CRASH_TEST_READY factors=\(boost.sessions.map { $0.factor })")
                fflush(stdout)
                _exit(42) // Deliberately bypass cleanup to exercise the recovery child.
            }
        }
    }
    var tooHot: Bool { ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical }
    func stopBoost() {
        let wasUpdating = updating
        updating = true
        if !boost.stop() { lastError = "Gamma 恢复未确认，请检查显示设置" }
        updating = wasUpdating
    }
    func fail(_ error: Error) {
        lastError = error.localizedDescription
        enabled = false
        resumeWork?.cancel()
        stopBoost()
        refresh()
    }
    func maintenance() {
        guard !updating else { return }
        do {
            try boost.checkIntegrity()
            try boost.repairStalledTriggers()
            refresh()
        } catch { fail(error) }
    }
    func environmentChanged() {
        resumeWork?.cancel()
        if sleeping || tooHot { reconcile(); return }
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        resumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func reconcile() {
        guard !updating else { return }
        updating = true
        let screens = supportedScreens
        if enabled && !sleeping && !tooHot && !screens.isEmpty {
            if !boost.isActive || !boost.matchesScreens(screens) {
                lastError = nil
                do { try boost.start(screens: screens) }
                catch { lastError = error.localizedDescription; enabled = false; boost.stop() }
            }
        } else {
            if !boost.stop() { lastError = "Gamma 恢复未确认，请检查显示设置" }
        }
        updating = false
        refresh()
    }
    func refresh() {
        guard status != nil else { return }
        toggleItem.state = enabled ? .on : .off
        toggleItem.isEnabled = !supportedScreens.isEmpty
        toggleItem.title = enabled ? "关闭额外亮度" : "开启额外亮度"
        updateSliderRange()
        status.button?.image = NSImage(systemSymbolName: enabled && boost.isActive ? "sun.max.fill" : "sun.max", accessibilityDescription: "XDR 亮度增强")
        if let lastError { infoItem.stringValue = lastError }
        else if supportedScreens.isEmpty { infoItem.stringValue = "当前内置屏幕没有可用 EDR 空间" }
        else if enabled && tooHot { infoItem.stringValue = "温度较高，增强已暂停" }
        else if enabled && sleeping { infoItem.stringValue = "睡眠期间已暂停" }
        else if let screen = supportedScreens.first {
            infoItem.stringValue = String(format: "系统当前 EDR 上限  %.2f×%@", Double(screen.maximumExtendedDynamicRangeColorComponentValue), enabled ? " · 已开启" : "")
        }
    }
    func updateSliderRange() {
        // Potential headroom is not currently usable headroom. Wait for EDR activation.
        let limit = supportedScreens.map { Double($0.maximumExtendedDynamicRangeColorComponentValue) }.min() ?? 1
        let active = enabled && boost.isActive && !sleeping && !tooHot && limit > 1.001
        slider.isEnabled = active
        let upper = active ? limit : max(Double(gain), 1.25)
        if slider.maxValue != upper { slider.maxValue = upper }
        if abs(slider.doubleValue - Double(gain)) > 0.00001 { slider.doubleValue = Double(gain) }
        let effective = GammaBoost.effectiveGain(requested: gain, headroom: CGFloat(limit))
        gainLabel.stringValue = active && effective + 0.001 < gain
            ? String(format: "目标 %.2f× · 当前可用 %.2f×", Double(gain), Double(effective))
            : String(format: "目标增强  %.2f×", Double(gain))
        if enabled && boost.isActive && !sleeping && !tooHot && !updating {
            updating = true
            do { try boost.apply(gain: gain, screens: supportedScreens) }
            catch { updating = false; fail(error); return }
            updating = false
        }
        slider.toolTip = active ? String(format: "目标范围：1.00–%.2f×；Gamma 映射，非实测物理倍率", limit) : "开启增强后，按系统当前 EDR 上限开放滑杆"
    }
    @objc func toggle() {
        enabled.toggle()
        if enabled { lastError = nil }
        reconcile()
    }
    @objc func reset() { enabled = false; reconcile() }
    @objc func slide(_ sender: NSSlider) {
        gain = CGFloat(min(max(sender.doubleValue, 1), slider.maxValue))
        UserDefaults.standard.set(Double(gain), forKey: "gain")
        do { try boost.apply(gain: gain, screens: supportedScreens) }
        catch { fail(error); return }
        gainLabel.stringValue = String(format: "目标增强  %.2f×", Double(gain))
    }
    @objc func screensChanged() {
        // EDR headroom updates also post this notification: only rebuild for actual topology changes.
        guard !updating else { return }
        if enabled && !sleeping && !tooHot && !boost.matchesScreens(supportedScreens) { reconcile() }
        else { refresh() }
    }
    @objc func thermalChanged() { reconcile() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showControls() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = status.button else { return }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationWillTerminate(_ notification: Notification) {
        resumeWork?.cancel()
        timer?.invalidate()
        stopBoost()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

}

if CommandLine.arguments.contains("--restore-gamma-on-eof") {
    exit(GammaRecovery.runHelper())
}
let app = NSApplication.shared
if CommandLine.arguments.contains("--gamma-snapshot") {
    let snapshots = NSScreen.screens.filter { CGDisplayIsBuiltin(displayID($0)) != 0 }.compactMap { try? GammaSnapshot.capture(displayID($0)) }
    if let data = try? JSONEncoder().encode(snapshots) { FileHandle.standardOutput.write(data) }
} else if CommandLine.arguments.contains("--probe") {
    print("Model: \(modelIdentifier())")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    for screen in NSScreen.screens {
        print("Display: \(screen.localizedName), builtin=\(CGDisplayIsBuiltin(displayID(screen))), pixels=\(CGDisplayCopyDisplayMode(displayID(screen))?.pixelWidth ?? 0)x\(CGDisplayCopyDisplayMode(displayID(screen))?.pixelHeight ?? 0), currentEDR=\(screen.maximumExtendedDynamicRangeColorComponentValue), potentialEDR=\(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)")
    }
} else {
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    exit(verificationStatus)
}
