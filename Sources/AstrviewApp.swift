import AppKit
import WebKit

final class AstrviewApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    static let dashboard = URL(string: "http://localhost:6185")!
    private var dashboardURL = AstrviewApp.dashboard
    private let launcher = LaunchPanel()
    private let surface = WorkspaceView(frame: NSRect(x: 0, y: 0, width: 360, height: 218))
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 218),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
    private var bot: BotProcess?
    private var project: URL?
    private var projectPicker: NSOpenPanel?
    private var state: State = .idle { didSet { updateStatusLabel() } }
    private var mode: LaunchMode = .hideWhenReady
    private var settingsPanel: NSPanel?
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?
    private var dockCheckbox: NSButton?
    private var settingsHideCheckbox: NSButton?
    private var projectLabel: NSTextField?
    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        super.init()
        preferences.register(defaults: ["showDockIcon": true, "hideAfterLaunch": true])
    }

    func applyDockPreference() {
        NSApp.setActivationPolicy(preferences.bool(forKey: "showDockIcon") ? .regular : .accessory)
    }
    private var version: String?
    private var didExpandTerminal = false
    private var animation: Timer?
    private var navigation: WKNavigation?
    private var attempts = 0
    private var quitting = false

    private enum State { case idle, starting, ready, stopped }
    private enum LaunchMode { case hideWhenReady, visible }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        installStatusItem()
        launcher.hideCheckbox.state = preferences.bool(forKey: "hideAfterLaunch") ? .on : .off
        launcher.hideCheckbox.target = self
        launcher.hideCheckbox.action = #selector(changeAutoHide(_:))
        window.title = "Astrview"
        window.contentView = surface
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = NSSize(width: 320, height: 186)
        launcher.launchButton.target = self
        launcher.launchButton.action = #selector(startFromLauncher)
        launcher.settingsButton.target = self
        launcher.settingsButton.action = #selector(showSettings)
        surface.restartButton.target = self
        surface.restartButton.action = #selector(restartBot)
        surface.retryButton.target = self
        surface.retryButton.action = #selector(reloadDashboard)
        surface.web.navigationDelegate = self
        launcher.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        main.addItem(app)
        let menu = NSMenu(title: "Astrview")
        app.submenu = menu
        let about = menu.addItem(withTitle: "关于 Astrview", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let repository = menu.addItem(withTitle: "在 GitHub 上查看 Astrview", action: #selector(openRepository), keyEquivalent: "")
        repository.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let show = menu.addItem(withTitle: "打开 Astrview", action: #selector(showInterface), keyEquivalent: "")
        show.target = self
        let select = menu.addItem(withTitle: "选择 AstrBot 项目…", action: #selector(selectProject), keyEquivalent: "o")
        select.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Astrview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (label, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"),
                                     ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: label, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image: NSImage?
        if let url = Bundle.main.url(forResource: "AstrviewMenuBar", withExtension: "png"),
           let template = NSImage(contentsOf: url) {
            template.size = NSSize(width: 21, height: 17.5)
            image = template
        } else {
            image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Astrview")
        }
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Astrview"
        item.button?.setAccessibilityLabel("Astrview")
        let menu = NSMenu()
        let status = NSMenuItem(title: "AstrBot 未启动", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLabel = status
        menu.addItem(.separator())
        for (title, action) in [("打开 Astrview", #selector(showInterface)), ("设置…", #selector(showSettings))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Astrview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "").target = NSApp
        item.menu = menu
        statusItem = item
        updateStatusLabel()
    }

    private func updateStatusLabel() {
        switch state {
        case .idle: statusLabel?.title = "AstrBot 未启动"
        case .starting: statusLabel?.title = "AstrBot 正在启动…"
        case .ready: statusLabel?.title = "AstrBot 正在运行"
        case .stopped: statusLabel?.title = "AstrBot 已停止"
        }
    }

    private func metadata(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string: [
            metadata("AstrviewDescription"),
            "作者：\(metadata("AstrviewAuthor"))　·　许可证：\(metadata("AstrviewLicense"))"
        ].joined(separator: "\n") + "\n\n")
        if let url = URL(string: metadata("AstrviewRepositoryURL")), url.scheme == "https" {
            credits.append(NSAttributedString(string: url.absoluteString, attributes: [.link: url]))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: metadata("AstrviewReleaseVersion"),
            .version: metadata("CFBundleVersion"),
            .credits: credits
        ])
    }

    @objc private func openRepository() {
        guard let url = URL(string: metadata("AstrviewRepositoryURL")), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showSettings() {
        if settingsPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 416, height: 275),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Astrview 设置"
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "AstrBot 项目目录")
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.frame = NSRect(x: 24, y: 90, width: 368, height: 20)
            let path = NSTextField(labelWithString: "")
            path.lineBreakMode = .byTruncatingMiddle
            path.textColor = .secondaryLabelColor
            path.frame = NSRect(x: 24, y: 63, width: 368, height: 20)
            projectLabel = path
            let choose = NSButton(title: "选择项目目录…", target: self, action: #selector(selectProject))
            choose.bezelStyle = .rounded
            choose.frame = NSRect(x: 17, y: 18, width: 150, height: 30)

            let heading = NSTextField(labelWithString: "显示与启动")
            heading.font = .systemFont(ofSize: 14, weight: .semibold)
            heading.frame = NSRect(x: 24, y: 231, width: 368, height: 20)
            let dock = NSButton(checkboxWithTitle: "显示 Dock 图标", target: self, action: #selector(changeDockIcon(_:)))
            dock.frame = NSRect(x: 23, y: 200, width: 369, height: 23)
            dockCheckbox = dock
            let hint = NSTextField(labelWithString: "关闭后，仍可通过菜单栏图标打开 Astrview。")
            hint.textColor = .secondaryLabelColor
            hint.font = .systemFont(ofSize: 12)
            hint.frame = NSRect(x: 44, y: 175, width: 348, height: 18)
            let hide = NSButton(checkboxWithTitle: "启动后隐藏", target: self, action: #selector(changeAutoHide(_:)))
            hide.frame = NSRect(x: 23, y: 141, width: 369, height: 23)
            settingsHideCheckbox = hide
            let divider = NSBox(frame: NSRect(x: 24, y: 124, width: 368, height: 1))
            divider.boxType = .separator
            [heading, dock, hint, hide, divider, label, path, choose].forEach { panel.contentView?.addSubview($0) }
            panel.center()
            settingsPanel = panel
        }
        dockCheckbox?.state = preferences.bool(forKey: "showDockIcon") ? .on : .off
        settingsHideCheckbox?.state = launcher.hideCheckbox.state
        refreshProjectLabel()
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel?.makeKeyAndOrderFront(nil)
    }

    @objc private func changeDockIcon(_ sender: NSButton) {
        preferences.set(sender.state == .on, forKey: "showDockIcon")
        applyDockPreference()
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel?.makeKeyAndOrderFront(nil)
    }

    @objc private func changeAutoHide(_ sender: NSButton) {
        launcher.hideCheckbox.state = sender.state
        settingsHideCheckbox?.state = sender.state
        preferences.set(sender.state == .on, forKey: "hideAfterLaunch")
    }

    private var savedProject: URL? {
        preferences.string(forKey: "projectDirectory").map { URL(fileURLWithPath: $0) }
    }

    private func refreshProjectLabel() {
        guard let projectLabel else { return }
        let path = (project ?? savedProject ?? BotConfiguration.discoverProject())?.path
        projectLabel.stringValue = path ?? "尚未找到包含 .astrbot 的目录"
        projectLabel.toolTip = path
    }

    @objc private func selectProject() { chooseProject(startMode: nil) }
    @objc private func startFromLauncher() { startBot(mode: launcher.hidesAfterLaunch ? .hideWhenReady : .visible) }
    @objc private func restartBot() { startFromLauncher() }

    private func chooseProject(startMode: LaunchMode?) {
        if let projectPicker { projectPicker.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = "选择含 .astrbot 的 AstrBot 项目目录"
        panel.message = "请选择已经初始化的 AstrBot 项目。Astrview 不会自动初始化或修改配置。"
        panel.prompt = "选择目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project ?? savedProject ?? FileManager.default.homeDirectoryForCurrentUser
        projectPicker = panel
        // There is no management window to attach a sheet to during initial launch.
        panel.begin { [weak self] response in
            guard let self else { return }
            self.projectPicker = nil
            guard response == .OK, let directory = panel.url else { return }
            guard BotConfiguration.isProject(directory) else {
                let alert = NSAlert()
                alert.messageText = "没有找到 .astrbot"
                alert.informativeText = "请选择已初始化的 AstrBot 项目目录，或先在终端中运行 astrbot init。"
                _ = alert.runModal()
                return
            }
            self.project = directory
            self.preferences.set(directory.path, forKey: "projectDirectory")
            self.refreshProjectLabel()
            if let startMode { self.startBot(mode: startMode) }
        }
    }

    private func startBot(mode: LaunchMode) {
        guard !quitting, state == .idle || state == .stopped else { return }
        guard let directory = [project, savedProject, BotConfiguration.discoverProject()].compactMap({ $0 })
            .first(where: BotConfiguration.isProject) else {
            chooseProject(startMode: mode)
            return
        }
        project = directory
        launch(in: directory, mode: mode)
    }

    private func launch(in directory: URL, mode: LaunchMode, configuration override: BotConfiguration? = nil,
                        shells: [URL] = BotShell.system) {
        state = .starting
        self.mode = mode
        version = nil
        didExpandTerminal = false
        surface.presentTerminal()
        surface.status.stringValue = "正在启动…"
        window.title = "Astrview — 启动终端"
        if !window.isVisible {
            window.setFrame(window.frameRect(forContentRect: launcher.frame), display: false)
        }
        let targetFrame = terminalFrame
        launcher.orderOut(nil)
        settingsPanel?.orderOut(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        animate(to: targetFrame, dock: 0, duration: 0.34) { [weak self] in
            guard let self else { return }
            self.didExpandTerminal = true
            self.openDashboardIfReady()
        }
        do {
            let configuration = try override ?? BotConfiguration.resolve(in: directory)
            let child = BotProcess()
            try child.start(configuration, shells: shells, output: { [weak self] text, ready in
                guard let self else { return }
                self.surface.append(text)
                if let ready, self.state == .starting {
                    self.version = ready
                    self.openDashboardIfReady()
                }
            }, exited: { [weak self] status in self?.botExited(status) })
            bot = child
            let shell = child.shell?.lastPathComponent ?? "shell"
            surface.setShell(shell)
            surface.append("[\(shell)] $ astrbot run\n")
        } catch {
            surface.append("\n[Astrview] \(error.localizedDescription)\n")
            botExited(nil)
        }
    }

    private var visibleScreen: NSRect {
        launcher.screen?.visibleFrame ?? window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1024, height: 700)
    }

    private var terminalFrame: NSRect {
        let region = visibleScreen
        let width = min(820, region.width)
        let height = min(492, region.height)
        return NSRect(x: region.midX - width / 2, y: region.midY - height / 2, width: width, height: height)
    }

    private func animate(to frame: NSRect, dock: CGFloat, duration: TimeInterval, completion: @escaping () -> Void = {}) {
        animation?.invalidate()
        animation = nil
        let start = window.frame
        let initialDock = surface.dockProgress
        let time = ProcessInfo.processInfo.systemUptime
        if !window.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
            surface.dockProgress = dock
            surface.layoutSubtreeIfNeeded()
            completion()
            return
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - time) / duration)
            let ease = CGFloat(t * t * (3 - 2 * t))
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * ease }
            self.window.setFrame(NSRect(x: mix(start.minX, frame.minX), y: mix(start.minY, frame.minY),
                                        width: mix(start.width, frame.width), height: mix(start.height, frame.height)), display: true)
            self.surface.dockProgress = mix(initialDock, dock)
            self.surface.layoutSubtreeIfNeeded()
            if t == 1 {
                timer.invalidate()
                self.animation = nil
                completion()
            }
        }
        animation = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func openDashboardIfReady() {
        guard !quitting, state == .starting, didExpandTerminal, let version else { return }
        state = .ready
        launcher.orderOut(nil)
        launcher.setStarting(false)
        window.title = "Astrview — AstrBot v\(version)"
        surface.status.stringValue = "AstrBot v\(version)"
        let dashboardFrame = visibleScreen
        if mode == .hideWhenReady {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderOut(nil)
        }
        surface.presentWeb()
        animate(to: dashboardFrame, dock: 1, duration: 0.52)
        if window.isVisible { reloadDashboard() }
    }

    @objc private func showInterface() {
        guard !quitting else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let projectPicker { projectPicker.makeKeyAndOrderFront(nil); return }
        if state == .idle {
            launcher.makeKeyAndOrderFront(nil)
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        if state == .ready, navigation == nil { reloadDashboard() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showInterface()
        return true
    }

    @objc private func reloadDashboard() {
        guard state == .ready else { return }
        attempts = 0
        surface.showWebMessage("正在连接 \(dashboardURL.absoluteString)…")
        loadDashboard()
    }

    private func loadDashboard() {
        attempts += 1
        navigation = surface.web.load(URLRequest(url: dashboardURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard state == .ready, navigation === self.navigation else { return }
        surface.showWebMessage(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        webFailed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webFailed(navigation, error: error)
    }

    private func webFailed(_ failed: WKNavigation?, error: Error) {
        guard state == .ready, let failed, failed === navigation else { return }
        let connectionErrors = [NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut]
        let urlError = error as NSError
        if attempts < 10, urlError.domain == NSURLErrorDomain, connectionErrors.contains(urlError.code) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.state == .ready, failed === self.navigation else { return }
                self.loadDashboard()
            }
        } else {
            surface.showWebMessage("无法打开 WebUI：\(error.localizedDescription)", retry: true)
        }
    }

    private func botExited(_ status: Int32?) {
        bot = nil
        if let status { surface.append("\n[Astrview] astrbot 已退出（\(status)）。\n") }
        if quitting {
            state = .stopped
            #if !ASTRVIEW_TEST
            NSApp.reply(toApplicationShouldTerminate: true)
            #endif
            return
        }
        state = .stopped
        navigation = nil
        surface.web.stopLoading()
        surface.showWebMessage("AstrBot 已停止，可在下方重新运行。")
        surface.status.stringValue = status == 0 ? "已停止" : "运行失败"
        surface.showTerminalRetry()
        launcher.setStarting(false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let bot else { return .terminateNow }
        if !quitting {
            quitting = true
            surface.status.stringValue = "正在停止 AstrBot…"
            bot.stop()
        }
        return .terminateLater
    }

    #if ASTRVIEW_TEST
    func testLaunch(in directory: URL, port: Int, shells: [URL] = BotShell.system) throws {
        dashboardURL = URL(string: "http://localhost:\(port)")!
        let original = try BotConfiguration.resolve(in: directory)
        var environment = original.environment
        environment["DASHBOARD_PORT"] = String(port)
        launch(in: directory, mode: launcher.hidesAfterLaunch ? .hideWhenReady : .visible,
               configuration: BotConfiguration(executable: original.executable, directory: directory, environment: environment),
               shells: shells)
    }
    var testWindow: NSWindow { window }
    var testLauncher: LaunchPanel { launcher }
    var testSettingsPanel: NSPanel? { settingsPanel }
    var testDockCheckbox: NSButton? { dockCheckbox }
    var testSettingsHideCheckbox: NSButton? { settingsHideCheckbox }
    var testStatusItem: NSStatusItem? { statusItem }
    var testStatusTitle: String? { statusLabel?.title }
    var testExpectedFrame: NSRect { visibleScreen }
    var testView: WorkspaceView { surface }
    var testStopped: Bool { state == .stopped }
    var testReady: Bool { state == .ready }
    #endif
}
