import AppKit
import WebKit

final class AstrviewApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    static let dashboard = URL(string: "http://localhost:6185")!
    private var dashboardURL = AstrviewApp.dashboard
    private let surface = WorkspaceView(frame: NSRect(x: 0, y: 0, width: 360, height: 218))
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 218),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
    private var bot: BotProcess?
    private var project: URL?
    private var state: State = .idle
    private var version: String?
    private var didExpandTerminal = false
    private var animation: Timer?
    private var navigation: WKNavigation?
    private var attempts = 0
    private var quitting = false

    private enum State { case idle, starting, ready, stopping, stopped }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window.title = "Astrview"
        window.contentView = surface
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = NSSize(width: 320, height: 186)
        surface.launchButton.target = self
        surface.launchButton.action = #selector(startBot)
        surface.stopButton.target = self
        surface.stopButton.action = #selector(terminalAction)
        surface.retryButton.target = self
        surface.retryButton.action = #selector(reloadDashboard)
        surface.web.navigationDelegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        main.addItem(app)
        let menu = NSMenu(title: "Astrview")
        app.submenu = menu
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

    @objc private func selectProject() { chooseProject(startOnSuccess: false) }

    private func chooseProject(startOnSuccess: Bool) {
        let panel = NSOpenPanel()
        panel.title = "选择含 .astrbot 的 AstrBot 项目目录"
        panel.message = "请选择已经初始化的 AstrBot 项目。Astrview 不会自动初始化或修改配置。"
        panel.prompt = "选择目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project ?? FileManager.default.homeDirectoryForCurrentUser
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let directory = panel.url else { return }
            guard BotConfiguration.isProject(directory) else {
                let alert = NSAlert()
                alert.messageText = "没有找到 .astrbot"
                alert.informativeText = "请选择已初始化的 AstrBot 项目目录，或先在终端中运行 astrbot init。"
                alert.beginSheetModal(for: self.window)
                return
            }
            self.project = directory
            UserDefaults.standard.set(directory.path, forKey: "projectDirectory")
            if startOnSuccess { self.startBot() }
        }
    }

    @objc private func startBot() {
        guard state == .idle || state == .stopped else { return }
        let saved = UserDefaults.standard.string(forKey: "projectDirectory").map { URL(fileURLWithPath: $0) }
        guard let directory = [project, saved, BotConfiguration.discoverProject()].compactMap({ $0 })
            .first(where: BotConfiguration.isProject) else {
            chooseProject(startOnSuccess: true)
            return
        }
        project = directory
        launch(in: directory)
    }

    private func launch(in directory: URL, configuration override: BotConfiguration? = nil) {
        state = .starting
        version = nil
        didExpandTerminal = false
        surface.presentTerminal()
        surface.status.stringValue = "正在启动…"
        surface.append("$ astrbot run\n")
        window.makeFirstResponder(nil)
        window.title = "Astrview — 启动终端"
        let region = visibleScreen
        let width = min(820, region.width)
        let height = min(492, region.height)
        animate(to: NSRect(x: region.midX - width / 2, y: region.midY - height / 2, width: width, height: height),
                dock: 0, duration: 0.34) { [weak self] in
            guard let self else { return }
            self.didExpandTerminal = true
            self.openDashboardIfReady()
        }
        do {
            let configuration = try override ?? BotConfiguration.resolve(in: directory)
            let child = BotProcess()
            try child.start(configuration, output: { [weak self] text, ready in
                guard let self else { return }
                self.surface.append(text)
                if let ready, self.state == .starting {
                    self.version = ready
                    self.openDashboardIfReady()
                }
            }, exited: { [weak self] status in self?.botExited(status) })
            bot = child
        } catch {
            surface.append("\n[Astrview] \(error.localizedDescription)\n")
            botExited(nil)
        }
    }

    private var visibleScreen: NSRect {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 700)
    }

    private func animate(to frame: NSRect, dock: CGFloat, duration: TimeInterval, completion: @escaping () -> Void = {}) {
        animation?.invalidate()
        let start = window.frame
        let initialDock = surface.dockProgress
        let time = ProcessInfo.processInfo.systemUptime
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
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
        guard state == .starting, didExpandTerminal, let version else { return }
        state = .ready
        window.title = "Astrview — AstrBot v\(version)"
        surface.status.stringValue = "AstrBot v\(version)"
        surface.presentWeb()
        surface.showWebMessage("正在连接 http://localhost:6185…")
        animate(to: visibleScreen, dock: 1, duration: 0.52)
        reloadDashboard()
    }

    @objc private func reloadDashboard() {
        guard state == .ready else { return }
        attempts = 0
        surface.showWebMessage("正在连接 http://localhost:6185…")
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

    @objc private func terminalAction() {
        if state == .stopped { startBot() }
        else { stopBot() }
    }

    private func stopBot() {
        guard let bot, state != .stopping else { return }
        state = .stopping
        surface.status.stringValue = "正在停止…"
        surface.stopButton.isEnabled = false
        bot.stop()
    }

    private func botExited(_ status: Int32?) {
        bot = nil
        if quitting {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        let requested = state == .stopping
        state = .stopped
        navigation = nil
        surface.web.stopLoading()
        surface.showWebMessage("AstrBot 已停止，可在下方重新运行。")
        surface.status.stringValue = requested || status == 0 ? "已停止" : "运行失败"
        surface.stopButton.title = "重试"
        surface.stopButton.isEnabled = true
        if let status { surface.append("\n[Astrview] astrbot 已退出（\(status)）。\n") }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard bot != nil else { return .terminateNow }
        quitting = true
        stopBot()
        return .terminateLater
    }

    #if ASTRVIEW_TEST
    func testLaunch(in directory: URL, port: Int) throws {
        dashboardURL = URL(string: "http://localhost:\(port)")!
        let original = try BotConfiguration.resolve(in: directory)
        var environment = original.environment
        environment["DASHBOARD_PORT"] = String(port)
        launch(in: directory, configuration: BotConfiguration(executable: original.executable, directory: directory, environment: environment))
    }
    func testStop() { stopBot() }
    var testWindow: NSWindow { window }
    var testExpectedFrame: NSRect { visibleScreen }
    var testView: WorkspaceView { surface }
    var testStopped: Bool { state == .stopped }
    #endif
}
