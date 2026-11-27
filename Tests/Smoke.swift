import AppKit

@main
struct Smoke {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func until(_ condition: () -> Bool, seconds: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    static func main() {
        var parser = BotOutput()
        let chunks = Data("启动中\r\n\u{1b}[32m AstrBot v4.2.0-rc.1 WebUI is ready\u{1b}[0m\r\n".utf8)
        require(parser.consume(chunks.prefix(2)).text.isEmpty, "buffer split UTF-8")
        let partial = parser.consume(chunks.dropFirst(2).dropLast(15))
        require(partial.text == "启动中\n" && partial.version == nil, "normalize newlines without premature ready")
        let ready = parser.consume(chunks.suffix(15))
        require(ready.text == " AstrBot v4.2.0-rc.1 WebUI is ready\n" && ready.version == "4.2.0-rc.1", "strip ANSI and detect split banner")
        require(parser.consume(Data("AstrBot v4.2.1 WebUI is ready\n".utf8)).version == nil, "report once")
        var missing = BotOutput()
        require(missing.consume(Data("AstrBot v4.2.0 WebUI is NOT ready\n".utf8)).version == nil, "reject not ready")
        require(missing.consume(Data("trailing text".utf8), end: true).text == "trailing text", "flush at EOF")

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "AstrviewSmoke.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let delegate = AstrviewApp(preferences: preferences)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        require(!delegate.testWindow.isVisible && delegate.testLauncher.isVisible, "only floating launcher visible")
        require(!delegate.testLauncher.styleMask.contains(.titled) && delegate.testLauncher.level == .floating, "borderless floating launcher")
        require(delegate.testLauncher.launchButton.attributedTitle.string == "运行astrbot", "launch button title")
        let launcher = delegate.testLauncher
        require(launcher.launchButton.focusRingType == .none, "no focus ring on the launch text")
        require(launcher.contentView is NSVisualEffectView && launcher.contentView?.layer?.borderWidth == 0,
                "translucent launcher background without a painted border")
        require(launcher.hidesAfterLaunch && launcher.hideCheckbox.title == "启动后隐藏", "auto-hide defaults on")
        launcher.settingsButton.performClick(nil)
        require(delegate.testSettingsPanel?.isVisible == true, "gear opens settings")
        require(delegate.testStatusItem?.button?.image?.isTemplate == true, "menu bar uses a template icon")
        require(delegate.testDockCheckbox?.state == .on, "Dock icon defaults on")
        delegate.testDockCheckbox?.performClick(nil)
        require(!preferences.bool(forKey: "showDockIcon") && app.activationPolicy() == .accessory, "turning Dock icon off applies and persists")
        require(delegate.testStatusItem?.isVisible == true, "menu bar item remains visible without Dock")
        delegate.testDockCheckbox?.performClick(nil)
        require(preferences.bool(forKey: "showDockIcon") && app.activationPolicy() == .regular, "Dock icon can be restored")
        delegate.testSettingsPanel?.close()
        launcher.hideCheckbox.performClick(nil)
        require(!launcher.hidesAfterLaunch && !preferences.bool(forKey: "hideAfterLaunch") && delegate.testSettingsHideCheckbox?.state == .off,
                "auto-hide checkbox stays synchronized and persists")
        let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        require(BotConfiguration.isProject(project), "recognize AstrBot project marker")
        let port = Int.random(in: 49_152...65_535)
        try! delegate.testLaunch(in: project, port: port)
        require(delegate.testWindow.isVisible && !delegate.testLauncher.isVisible, "visible mode opens management window")
        require(until({ delegate.testView.testLog.contains("mock: stderr") && delegate.testWindow.frame.width >= min(815, delegate.testExpectedFrame.width - 1) }), "terminal expands and merges output")
        require(delegate.testWindow.title.contains("启动终端") && delegate.testView.testWebFrame.height == 0, "terminal-only stage")
        require(until({ delegate.testView.dockProgress == 1 }), "ready banner expands window and docks terminal")
        require(delegate.testWindow.frame.equalTo(delegate.testExpectedFrame), "use screen visible frame")
        require(!delegate.testWindow.styleMask.contains(.fullScreen), "never enters macOS full-screen mode")
        require(delegate.testView.testTerminalFrame.minY == 0 && delegate.testView.testWebFrame.height > 0, "terminal below WebView")
        let workspace = delegate.testView
        let originalHeight = workspace.testTerminalFrame.height
        workspace.testResizeTerminal(by: 32)
        let draggedHeight = workspace.testTerminalFrame.height
        require(draggedHeight > originalHeight, "terminal divider increases the docked height")
        workspace.testToggleMaximize()
        require(workspace.testTerminalFrame.height == workspace.bounds.height && workspace.testWebFrame.height == 0,
                "maximize terminal inside the main window")
        workspace.testToggleMaximize()
        require(workspace.testTerminalFrame.height == draggedHeight, "restore custom height after maximizing")
        workspace.testMinimize()
        require(workspace.testTerminalFrame.minY == 0 && workspace.testTerminalFrame.height == workspace.testTerminalBar.height
                && workspace.testTerminalLogHidden, "minimize to the terminal title bar at the bottom")
        workspace.testToggleMaximize()
        require(workspace.testTerminalFrame.height == draggedHeight && !workspace.testTerminalLogHidden,
                "restore custom height after minimizing")
        require(workspace.testLog.contains("mock: stdout"), "retain stdout after resizing")
        let visibleLoaded = until({ !workspace.web.isLoading && workspace.web.url?.host == "localhost" && workspace.web.url?.port == port && workspace.webMessage.stringValue.isEmpty }, seconds: 10)
        if !visibleLoaded {
            print("Visible dashboard: \(workspace.web.url?.absoluteString ?? "nil"), \(workspace.webMessage.stringValue)\n\(workspace.testLog)")
        }
        require(visibleLoaded, "WKWebView opened localhost dashboard")
        var text: String?
        delegate.testView.web.evaluateJavaScript("document.body.textContent") { value, _ in text = value as? String }
        require(until({ text?.contains("Mock AstrBot Dashboard") == true }), "render mock dashboard")
        require(delegate.testView.testLog.contains("[zsh]"), "use native zsh by default")
        delegate.testWindow.performClose(nil)
        require(!delegate.testWindow.isVisible && delegate.testReady, "closing management window leaves AstrBot running")
        require(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false) && delegate.testWindow.isVisible,
                "Dock reopen restores management window")
        require(delegate.applicationShouldTerminate(app) == .terminateLater, "quit waits for AstrBot")
        require(until({ delegate.testStopped && delegate.applicationShouldTerminate(app) == .terminateNow }), "stop managed process on quit")
        require(delegate.testView.testLog.contains("mock: stopped"), "quit signal reaches AstrBot through exec")
        delegate.testWindow.orderOut(nil)

        preferences.set(true, forKey: "hideAfterLaunch")
        preferences.set(false, forKey: "showDockIcon")
        let hidden = AstrviewApp(preferences: preferences)
        hidden.applyDockPreference()
        hidden.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let fallback = [URL(fileURLWithPath: "/nonexistent-astrview-test-zsh"), BotShell.system[1]]
        let hiddenPort = (port == 65_535) ? port - 1 : port + 1
        try! hidden.testLaunch(in: project, port: hiddenPort, shells: fallback)
        require(!hidden.testLauncher.isVisible && hidden.testWindow.isVisible,
                "auto-hide mode shows the startup console")
        require(until({ hidden.testView.testLog.contains("mock: stderr") }) && hidden.testWindow.isVisible
                && hidden.testView.testWebFrame.height == 0, "logs are visible before auto-hiding")
        require(until({ hidden.testReady }), "background AstrBot becomes ready")
        require(!hidden.testLauncher.isVisible && !hidden.testWindow.isVisible, "background mode hides all windows when ready")
        require(hidden.testView.testLog.contains("[bash]"), "fallback to native Bash if zsh is unavailable")
        require(hidden.testStatusTitle == "AstrBot 正在运行", "menu bar reports running status")
        let showAction = hidden.testStatusItem?.menu?.item(withTitle: "打开 Astrview")
        require(showAction != nil && app.sendAction(showAction!.action!, to: showAction!.target, from: showAction)
                && hidden.testWindow.isVisible, "menu bar reopens management window without Dock icon")
        let loaded = until({ !hidden.testView.web.isLoading && hidden.testView.web.url?.port == hiddenPort && hidden.testView.webMessage.stringValue.isEmpty }, seconds: 8)
        if !loaded {
            print("Background dashboard: \(hidden.testView.web.url?.absoluteString ?? "nil"), \(hidden.testView.webMessage.stringValue)\n\(hidden.testView.testLog)")
        }
        require(loaded, "dashboard loads after reopening background launch")
        require(hidden.applicationShouldTerminate(app) == .terminateLater && until({ hidden.testStopped }), "quit stops background process")
        print("PASS: parser, floating launcher, both launch modes, zsh/Bash, WKWebView, close/reopen/quit")
    }
}
