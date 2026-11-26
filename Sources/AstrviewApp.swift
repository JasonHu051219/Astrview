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
    private var state: State = .idle
    private var mode: LaunchMode = .background
    private var version: String?
    private var didExpandTerminal = false
    private var animation: Timer?
    private var navigation: WKNavigation?
    private var attempts = 0
    private var quitting = false

    private enum State { case idle, starting, ready, stopped }
    private enum LaunchMode { case background, visible }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window.title = "Astrview"
        window.contentView = surface
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = NSSize(width: 320, height: 186)
        launcher.launchButton.target = self
        launcher.launchButton.action = #selector(startInBackground)
        launcher.visibleLaunchButton.target = self
        launcher.visibleLaunchButton.action = #selector(startWithoutHiding)
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

    @objc private func selectProject() { chooseProject(startMode: nil) }
    @objc private func startInBackground() { startBot(mode: .background) }
    @objc private func startWithoutHiding() {
        launcher.collapseOptions()
        startBot(mode: .visible)
    }
    @objc private func restartBot() { startBot(mode: .visible) }

    private func chooseProject(startMode: LaunchMode?) {
        if let projectPicker { projectPicker.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = "选择含 .astrbot 的 AstrBot 项目目录"
        panel.message = "请选择已经初始化的 AstrBot 项目。Astrview 不会自动初始化或修改配置。"
        panel.prompt = "选择目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project ?? FileManager.default.homeDirectoryForCurrentUser
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
            UserDefaults.standard.set(directory.path, forKey: "projectDirectory")
            if let startMode { self.startBot(mode: startMode) }
        }
    }

    private func startBot(mode: LaunchMode) {
        guard !quitting, state == .idle || state == .stopped else { return }
        let saved = UserDefaults.standard.string(forKey: "projectDirectory").map { URL(fileURLWithPath: $0) }
        guard let directory = [project, saved, BotConfiguration.discoverProject()].compactMap({ $0 })
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
        didExpandTerminal = mode == .background
        surface.presentTerminal()
        surface.status.stringValue = "正在启动…"
        window.title = "Astrview — 启动终端"
        launcher.setStarting(true)
        if mode == .visible {
            if !window.isVisible {
                window.setFrame(window.frameRect(forContentRect: launcher.frame), display: false)
            }
            launcher.orderOut(nil)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            animate(to: terminalFrame, dock: 0, duration: 0.34) { [weak self] in
                guard let self else { return }
                self.didExpandTerminal = true
                self.openDashboardIfReady()
            }
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
        surface.presentWeb()
        animate(to: visibleScreen, dock: 1, duration: 0.52)
        if window.isVisible { reloadDashboard() }
    }

    @objc private func showInterface() {
        guard !quitting else { return }
        if let projectPicker { projectPicker.makeKeyAndOrderFront(nil); return }
        if state == .idle || (state == .starting && mode == .background) {
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
        let failedWhileHidden = state == .starting && mode == .background
        state = .stopped
        navigation = nil
        surface.web.stopLoading()
        surface.showWebMessage("AstrBot 已停止，可在下方重新运行。")
        surface.status.stringValue = status == 0 ? "已停止" : "运行失败"
        surface.showTerminalRetry()
        if failedWhileHidden {
            launcher.orderOut(nil)
            launcher.setStarting(false)
            window.setFrame(terminalFrame, display: false)
            showInterface()
        }
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
    func testLaunch(in directory: URL, port: Int, background: Bool, shells: [URL] = BotShell.system) throws {
        dashboardURL = URL(string: "http://localhost:\(port)")!
        let original = try BotConfiguration.resolve(in: directory)
        var environment = original.environment
        environment["DASHBOARD_PORT"] = String(port)
        launch(in: directory, mode: background ? .background : .visible,
               configuration: BotConfiguration(executable: original.executable, directory: directory, environment: environment),
               shells: shells)
    }
    var testWindow: NSWindow { window }
    var testLauncher: LaunchPanel { launcher }
    var testExpectedFrame: NSRect { visibleScreen }
    var testView: WorkspaceView { surface }
    var testStopped: Bool { state == .stopped }
    var testReady: Bool { state == .ready }
    #endif
}
