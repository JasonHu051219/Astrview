import AppKit
import WebKit

private final class TerminalResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.28, green: 0.33, blue: 0.42, alpha: 1).setFill()
        NSRect(x: 0, y: 2, width: bounds.width, height: 1).fill()
    }
    private var startY: CGFloat = 0

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }

    override func mouseDown(with event: NSEvent) { startY = event.locationInWindow.y }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.locationInWindow.y - startY)
        startY = event.locationInWindow.y
    }
}

final class WorkspaceView: NSView {
    let restartButton = NSButton(title: "重试", target: nil, action: nil)
    let retryButton = NSButton(title: "重新加载", target: nil, action: nil)
    let status = NSTextField(labelWithString: "正在启动…")
    let webMessage = NSTextField(labelWithString: "正在连接 http://localhost:6185…")
    let web = WKWebView()
    private let webArea = NSView()
    private let webOverlay = NSView()
    private let terminal = NSView()
    private let bar = NSView()
    private let terminalTitle = NSTextField(labelWithString: "终端输出  /  astrbot run")
    private let log = NSTextView()
    private let scroll = NSScrollView()
    private let resizeHandle = TerminalResizeHandle()
    private let minimizeButton = NSButton()
    private let maximizeButton = NSButton()
    private let barHeight: CGFloat = 36
    private enum TerminalSize { case docked, minimized, maximized }
    private var terminalSize: TerminalSize = .docked
    private var preferredHeight: CGFloat?
    private let ink = NSColor(srgbRed: 0.067, green: 0.082, blue: 0.118, alpha: 1)
    private let light = NSColor(srgbRed: 0.84, green: 0.89, blue: 0.96, alpha: 1)
    private var followOutput = true
    private var showingTerminal = false
    private var showingWeb = false
    var dockProgress: CGFloat = 0 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(webArea)
        addSubview(terminal)
        webArea.addSubview(web)
        webArea.addSubview(webOverlay)
        webOverlay.addSubview(webMessage)
        webOverlay.addSubview(retryButton)
        terminal.addSubview(bar)
        terminal.addSubview(scroll)
        bar.addSubview(terminalTitle)
        bar.addSubview(status)
        bar.addSubview(restartButton)
        bar.addSubview(minimizeButton)
        bar.addSubview(maximizeButton)
        addSubview(resizeHandle)
        resizeHandle.isHidden = true
        resizeHandle.onDrag = { [weak self] delta in self?.resizeTerminal(by: delta) }
        configure(minimizeButton, symbol: "minus", label: "最小化终端", action: #selector(minimizeTerminal))
        configure(maximizeButton, symbol: "square", label: "最大化终端", action: #selector(toggleMaximizeTerminal))

        restartButton.bezelStyle = .rounded
        restartButton.controlSize = .small
        restartButton.isHidden = true
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

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .thin))
        button.imagePosition = .imageOnly
        button.contentTintColor = light
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.isHidden = true
    }

    private var dockedHeight: CGFloat {
        let height = bounds.height
        return min(max(barHeight, height - 90), max(barHeight, preferredHeight ?? min(224, max(142, height * 0.24))))
    }

    private var terminalControlsAvailable: Bool { showingWeb && dockProgress >= 1 }

    func showTerminalRetry() {
        restartButton.isHidden = false
        needsLayout = true
    }

    private func updateTerminalLayout() {
        let label = terminalSize == .docked ? "最大化终端" : "恢复终端高度"
        maximizeButton.toolTip = label
        maximizeButton.setAccessibilityLabel(label)
        minimizeButton.isEnabled = terminalSize != .minimized
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @objc private func minimizeTerminal() {
        guard terminalControlsAvailable else { return }
        terminalSize = .minimized
        updateTerminalLayout()
    }

    @objc private func toggleMaximizeTerminal() {
        guard terminalControlsAvailable else { return }
        terminalSize = terminalSize == .docked ? .maximized : .docked
        updateTerminalLayout()
    }

    private func resizeTerminal(by delta: CGFloat) {
        guard terminalControlsAvailable, delta != 0 else { return }
        let upper = max(barHeight, bounds.height - 90)
        let origin = min(terminal.frame.height, upper)
        let next = min(upper, max(barHeight, origin + delta))
        if next <= barHeight {
            terminalSize = .minimized
        } else {
            preferredHeight = next
            terminalSize = .docked
        }
        updateTerminalLayout()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let height = bounds.height
        guard showingTerminal else { return }
        let bottom: CGFloat
        switch terminalSize {
        case .docked: bottom = dockedHeight
        case .minimized: bottom = barHeight
        case .maximized: bottom = height
        }
        let consoleHeight = showingWeb ? height + (min(height, bottom) - height) * dockProgress : height
        terminal.frame = CGRect(x: 0, y: 0, width: width, height: consoleHeight)
        minimizeButton.isHidden = !terminalControlsAvailable
        maximizeButton.isHidden = !terminalControlsAvailable
        resizeHandle.isHidden = !terminalControlsAvailable || terminalSize == .maximized
        if !resizeHandle.isHidden {
            resizeHandle.frame = CGRect(x: 0, y: max(0, consoleHeight - 3), width: width, height: 7)
        }
        bar.frame = CGRect(x: 0, y: max(0, consoleHeight - barHeight), width: width, height: barHeight)
        terminalTitle.frame = CGRect(x: 15, y: 10, width: min(230, width * 0.51), height: 16)
        let statusX = terminalTitle.frame.maxX + 6
        let controlsWidth: CGFloat = terminalControlsAvailable ? 62 : 12
        let restartWidth: CGFloat = restartButton.isHidden ? 0 : 78
        status.frame = CGRect(x: statusX, y: 10, width: max(0, width - statusX - controlsWidth - restartWidth - 7), height: 15)
        restartButton.frame = CGRect(x: width - controlsWidth - restartWidth, y: 5, width: restartWidth, height: 26)
        minimizeButton.frame = CGRect(x: width - 58, y: 4, width: 24, height: 28)
        maximizeButton.frame = CGRect(x: width - 32, y: 4, width: 24, height: 28)
        scroll.frame = CGRect(x: 0, y: 0, width: width, height: bar.frame.minY)
        scroll.isHidden = bar.frame.minY <= 0
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
        terminalSize = .docked
        terminal.isHidden = false
        webArea.isHidden = true
        restartButton.isHidden = true
        terminalTitle.stringValue = "终端输出  /  astrbot run"
        log.string = ""
        followOutput = true
        dockProgress = 0
    }

    func setShell(_ name: String) {
        terminalTitle.stringValue = "\(name)  /  astrbot run"
    }

    func presentWeb() {
        showingWeb = true
        webArea.isHidden = false
        updateTerminalLayout()
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
    var testTerminalBar: NSRect { bar.frame }
    var testTerminalLogHidden: Bool { scroll.isHidden }
    func testResizeTerminal(by delta: CGFloat) { resizeHandle.onDrag?(delta) }
    func testToggleMaximize() { maximizeButton.performClick(nil) }
    func testMinimize() { minimizeButton.performClick(nil) }
    #endif
}
