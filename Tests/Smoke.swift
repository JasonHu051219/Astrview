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
        let delegate = AstrviewApp()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        require(delegate.testWindow.isVisible && !delegate.testView.launchButton.isHiddenOrHasHiddenAncestor, "launch screen visible")
        require(delegate.testView.launchButton.title == "运行astrbot", "launch button title")
        let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        require(BotConfiguration.isProject(project), "recognize AstrBot project marker")
        let port = Int.random(in: 49_152...65_535)
        try! delegate.testLaunch(in: project, port: port)
        require(until({ delegate.testView.testLog.contains("mock: stderr") && delegate.testWindow.frame.width >= min(815, delegate.testExpectedFrame.width - 1) }), "terminal expands and merges output")
        require(delegate.testWindow.title.contains("启动终端") && delegate.testView.testWebFrame.height == 0, "terminal-only stage")
        require(until({ delegate.testView.dockProgress == 1 }), "ready banner expands window and docks terminal")
        require(delegate.testWindow.frame.equalTo(delegate.testExpectedFrame), "use screen visible frame")
        require(!delegate.testWindow.styleMask.contains(.fullScreen), "never enters macOS full-screen mode")
        require(delegate.testView.testTerminalFrame.minY == 0 && delegate.testView.testWebFrame.height > 0, "terminal below WebView")
        require(delegate.testView.testLog.contains("mock: stdout"), "retain stdout after resizing")
        require(until({ !delegate.testView.web.isLoading && delegate.testView.web.url?.host == "localhost" && delegate.testView.web.url?.port == port && delegate.testView.webMessage.stringValue.isEmpty }), "WKWebView opened localhost dashboard")
        var text: String?
        delegate.testView.web.evaluateJavaScript("document.body.textContent") { value, _ in text = value as? String }
        require(until({ text?.contains("Mock AstrBot Dashboard") == true }), "render mock dashboard")
        delegate.testStop()
        require(until({ delegate.testStopped }), "stop managed process")
        print("PASS: parser, process output, both window stages, WKWebView, stop")
    }
}
