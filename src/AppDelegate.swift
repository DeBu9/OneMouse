import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let pointer = PointerController()
    private let scroll = ScrollController()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例：已经有同名应用在跑就直接退出，避免重复监听与双图标
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .contains(where: { $0.processIdentifier != getpid() }) {
            NSApp.terminate(nil)
            return
        }

        Prefs.migrateIfNeeded()
        Prefs.register()
        setupStatusItem()
        applySavedState()
        scroll.requestPermissionIfNeeded()
        rebuildMenu()
        installSignalHandlers()
        writeStatus()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.rebuildMenu() }

        // 用户从系统设置授权后切回来，立即接上监听，不用再点菜单
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.scroll.enabled, !self.scroll.isTapping, self.scroll.hasPermission {
                self.scroll.retryStart()
                self.rebuildMenu()
            }
        }

        // 睡眠唤醒后系统会重置加速度，补回
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.reapplyPointerState() }
    }

    private func reapplyPointerState() {
        guard let pointer = pointer else { return }
        if UserDefaults.standard.bool(forKey: Prefs.pointerLinear), !pointer.isLinear {
            pointer.setLinear(true)
        }
        if scroll.enabled, !scroll.isTapping, scroll.hasPermission {
            scroll.retryStart()
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scroll.stop()
        if UserDefaults.standard.bool(forKey: Prefs.pointerLinear) {
            pointer?.setLinear(false)
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "OneMouse")
            image?.isTemplate = true
            button.image = image
        }
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        if scroll.enabled, !scroll.isTapping, scroll.hasPermission {
            scroll.retryStart()
        }
        DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
    }

    private func applySavedState() {
        let defaults = UserDefaults.standard
        if let linear = defaults.object(forKey: Prefs.pointerLinear) as? Bool {
            pointer?.setLinear(linear)
        }

        scroll.speedLevel = defaults.integer(forKey: Prefs.scrollSpeed)
        scroll.enabled = defaults.bool(forKey: Prefs.scrollSmooth)
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let pointerItem = NSMenuItem(
            title: "指针：关闭加速（线性）",
            action: #selector(togglePointer),
            keyEquivalent: ""
        )
        pointerItem.target = self
        pointerItem.state = pointer?.isLinear == true ? .on : .off
        pointerItem.isEnabled = pointer != nil
        menu.addItem(pointerItem)

        let scrollItem = NSMenuItem(
            title: "滚轮：平滑",
            action: #selector(toggleScroll),
            keyEquivalent: ""
        )
        scrollItem.target = self
        scrollItem.state = scroll.enabled ? .on : .off
        menu.addItem(scrollItem)

        let speedItem = NSMenuItem(title: "平滑强度", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for (index, name) in ["轻", "中", "强"].enumerated() {
            let item = NSMenuItem(title: name, action: #selector(pickSpeed(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = index == scroll.speedLevel ? .on : .off
            speedMenu.addItem(item)
        }
        speedItem.submenu = speedMenu
        menu.addItem(speedItem)

        let loginItem = NSMenuItem(
            title: "开机自启",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLoginItemEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        if !scroll.hasPermission {
            let authItem = NSMenuItem(
                title: "未授权辅助功能 — 点此处理",
                action: #selector(promptPermission),
                keyEquivalent: ""
            )
            authItem.target = self
            menu.addItem(authItem)

            let addItem = NSMenuItem(
                title: "   （列表里没有 OneMouse？点这里手动添加）",
                action: #selector(revealAppForManualAdd),
                keyEquivalent: ""
            )
            addItem.target = self
            menu.addItem(addItem)

            let hintItem = NSMenuItem(
                title: "   （已勾选但仍无效：把开关关掉再打开一次）",
                action: nil,
                keyEquivalent: ""
            )
            hintItem.isEnabled = false
            menu.addItem(hintItem)
        }

        let status = NSMenuItem(
            title: statusLine(),
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        writeStatus()
    }

    @objc private func toggleLoginItem() {
        let turnOn = !isLoginItemEnabled
        do {
            if turnOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("OneMouse: 登录项设置失败 %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = turnOn ? "开机自启设置失败" : "取消开机自启失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
        rebuildMenu()
    }

    private var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 落一份状态到 /tmp，方便从外部确认授权与监听是否真的生效
    private func writeStatus() {
        let accel = pointer.map { String(format: "%.0f", $0.currentValue) } ?? "n/a"
        let text = """
        pid=\(getpid())
        bundle=\(Bundle.main.bundlePath)
        accessibilityTrusted=\(AXIsProcessTrusted() ? 1 : 0)
        scrollEnabled=\(scroll.enabled ? 1 : 0)
        scrollTapActive=\(scroll.isTapping ? 1 : 0)
        hidMouseAcceleration=\(accel)

        """
        try? text.write(toFile: "/tmp/onemouse-status.txt", atomically: true, encoding: .utf8)
    }

    private func statusLine() -> String {
        guard let pointer = pointer else { return "指针层不可用" }
        let value = pointer.currentValue
        let state = value <= 0 ? "线性" : String(format: "加速 %.0f", value)
        let scrollState = !scroll.enabled ? "关" : (scroll.isTapping ? "✓" : "待授权")
        return "加速度 \(state) · 滚动 \(scrollState)"
    }

    @objc private func togglePointer() {
        guard let pointer = pointer else { return }
        let target = !(pointer.isLinear)
        pointer.setLinear(target)
        UserDefaults.standard.set(target, forKey: Prefs.pointerLinear)
        rebuildMenu()
    }

    @objc private func toggleScroll() {
        scroll.enabled.toggle()
        UserDefaults.standard.set(scroll.enabled, forKey: Prefs.scrollSmooth)
        rebuildMenu()
    }

    @objc private func pickSpeed(_ sender: NSMenuItem) {
        scroll.speedLevel = sender.tag
        UserDefaults.standard.set(sender.tag, forKey: Prefs.scrollSpeed)
        rebuildMenu()
    }

    /// 直接打开「隐私与安全性 → 辅助功能」面板
    private func openAccessibilityPane() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for url in urls {
            if let u = URL(string: url), NSWorkspace.shared.open(u) { return }
        }
    }

    @objc private func promptPermission() {
        scroll.requestPermissionIfNeeded()
        openAccessibilityPane()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.scroll.retryStart()
            self?.rebuildMenu()
        }
    }

    /// 在访达里选中应用本体，方便在辅助功能面板点「+」手动添加
    @objc private func revealAppForManualAdd() {
        let path = Bundle.main.bundlePath
        openAccessibilityPane()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        let alert = NSAlert()
        alert.messageText = "在「辅助功能」列表点 + 号，选这个 App"
        alert.informativeText = "已在访达中选中：\n\(path)\n\n如果列表里已有 OneMouse 但没打勾，直接打勾即可。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
