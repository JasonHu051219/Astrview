import AppKit
import WebKit

final class WorkspaceView: NSView {
    let launchButton = NSButton(title: "运行astrbot", target: nil, action: nil)
    let stopButton = NSButton(title: "停止", target: nil, action: nil)
    let retryButton = NSButton(title: "重新加载", target: nil, action: nil)
    let status = NSTextField(labelWithString: "正在启动…")
    let webMessage = NSTextField(labelWithString: "正在连接 http://localhost:6185…")
    let web = WKWebView()
    private let launchScreen = NSView()
    private let webArea = NSView()
    private let webOverlay = NSView()
    private let terminal = NSView()
    private let bar = NSView()
    private let terminalTitle = NSTextField(labelWithString: "终端输出  /  astrbot run")
    private let log = NSTextView()
    private let scroll = NSScrollView()
    private let ink = NSColor(srgbRed: 0.067, green: 0.082, blue: 0.118, alpha: 1)
    private let light = NSColor(srgbRed: 0.84, green: 0.89, blue: 0.96, alpha: 1)
    private var followOutput = true
    private var showingTerminal = false
    private var showingWeb = false
    var dockProgress: CGFloat = 0 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(launchScreen)
        addSubview(webArea)
        addSubview(terminal)
        launchScreen.addSubview(launchButton)
        webArea.addSubview(web)
        webArea.addSubview(webOverlay)
        webOverlay.addSubview(webMessage)
        webOverlay.addSubview(retryButton)
        terminal.addSubview(bar)
        terminal.addSubview(scroll)
        bar.addSubview(terminalTitle)
        bar.addSubview(status)
        bar.addSubview(stopButton)

        launchButton.isBordered = false
        launchButton.wantsLayer = true
        launchButton.layer?.backgroundColor = NSColor(srgbRed: 0.12, green: 0.36, blue: 0.93, alpha: 1).cgColor
        launchButton.layer?.cornerRadius = 14
        launchButton.attributedTitle = NSAttributedString(string: "运行astrbot", attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white
        ])
        launchButton.keyEquivalent = "\r"
        launchButton.setAccessibilityLabel("运行astrbot")
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        bar.appearance = NSAppearance(named: .darkAqua)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.14, blue: 0.20, alpha: 1).cgColor
        terminalTitle.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        terminalTitle.textColor = light
        status.textColor = NSColor(srgbRed: 0.58, green: 0.70, blue: 0.85, alpha: 1)
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.alignment = .right
        terminalTitle.lineBreakMode = .byTruncatingTail
        status.lineBreakMode = .byTruncatingTail

        scroll.drawsBackground = true
        scroll.backgroundColor = ink
        scroll.hasVerticalScroller = true
        scroll.documentView = log
        log.backgroundColor = ink
        log.textColor = light
        log.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        log.isEditable = false
        log.isSelectable = true
        log.isRichText = false
        log.isAutomaticLinkDetectionEnabled = false
        log.isVerticallyResizable = true
        log.isHorizontallyResizable = false
        log.autoresizingMask = [.width]
        log.textContainer?.widthTracksTextView = true
        log.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        log.textContainerInset = NSSize(width: 12, height: 10)
        log.setAccessibilityLabel("AstrBot 终端输出")
        webArea.wantsLayer = true
        webArea.layer?.masksToBounds = true
        webOverlay.wantsLayer = true
        webOverlay.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        webMessage.alignment = .center
        webMessage.lineBreakMode = .byTruncatingTail
        retryButton.bezelStyle = .rounded
        webArea.isHidden = true
        terminal.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let width = bounds.width
        let height = bounds.height
        launchScreen.frame = bounds
        launchButton.frame = CGRect(x: (width - 184) / 2, y: (height - 54) / 2, width: 184, height: 54)
        guard showingTerminal else { return }
        let bottom = min(height, max(142, min(224, height * 0.24)))
        let consoleHeight = showingWeb ? height + (bottom - height) * dockProgress : height
        terminal.frame = CGRect(x: 0, y: 0, width: width, height: consoleHeight)
        let barHeight: CGFloat = 36
        bar.frame = CGRect(x: 0, y: max(0, consoleHeight - barHeight), width: width, height: barHeight)
        terminalTitle.frame = CGRect(x: 15, y: 10, width: min(230, width * 0.51), height: 16)
        let statusX = terminalTitle.frame.maxX + 6
        status.frame = CGRect(x: statusX, y: 10, width: max(0, width - statusX - 97), height: 15)
        stopButton.frame = CGRect(x: width - 90, y: 5, width: 78, height: 26)
        scroll.frame = CGRect(x: 0, y: 0, width: width, height: bar.frame.minY)
        webArea.frame = CGRect(x: 0, y: consoleHeight, width: width, height: max(0, height - consoleHeight))
        web.frame = webArea.bounds
        webOverlay.frame = webArea.bounds
        webMessage.frame = CGRect(x: 16, y: webArea.bounds.midY + 6, width: max(0, width - 32), height: 24)
        retryButton.frame = CGRect(x: (width - 120) / 2, y: webArea.bounds.midY - 30, width: 120, height: 28)
        if followOutput { log.scrollToEndOfDocument(nil) }
    }

    func presentTerminal() {
        showingTerminal = true
        showingWeb = false
        launchScreen.isHidden = true
        terminal.isHidden = false
        webArea.isHidden = true
        stopButton.title = "停止"
        stopButton.isEnabled = true
        log.string = ""
        followOutput = true
        dockProgress = 0
    }

    func presentWeb() {
        showingWeb = true
        webArea.isHidden = false
        needsLayout = true
    }

    func showWebMessage(_ message: String?, retry: Bool = false) {
        webOverlay.isHidden = message == nil
        webMessage.stringValue = message ?? ""
        retryButton.isHidden = !retry
    }

    func append(_ text: String) {
        guard !text.isEmpty, let storage = log.textStorage else { return }
        let visible = scroll.contentView.bounds
        followOutput = log.bounds.height - visible.maxY < 24
        storage.beginEditing()
        storage.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: light
        ]))
        if storage.length > 400_000 {
            let excess = storage.length - 330_000
            let cut = (storage.string as NSString).lineRange(for: NSRange(location: excess, length: 0)).location
            storage.deleteCharacters(in: NSRange(location: 0, length: cut > 0 ? cut : excess))
        }
        storage.endEditing()
        if followOutput { log.scrollToEndOfDocument(nil) }
    }

    #if ASTRVIEW_TEST
    var testLog: String { log.string }
    var testTerminalFrame: NSRect { terminal.frame }
    var testWebFrame: NSRect { webArea.frame }
    #endif
}
