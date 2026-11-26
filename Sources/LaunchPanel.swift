import AppKit

/// Both rows share one blue surface; expanding grows the panel downward without moving its top edge.
final class LaunchPanel: NSPanel {
    private static let collapsedHeight: CGFloat = 54
    private static let optionHeight: CGFloat = 46
    private let buttonSurface = NSView()
    let launchButton = NSButton(title: "运行astrbot", target: nil, action: nil)
    let optionsButton = NSButton(title: "", target: nil, action: nil)
    let visibleLaunchButton = NSButton(title: "启动astrbot（不隐藏）", target: nil, action: nil)
    private var expanded = false

    init() {
        let rect = NSRect(x: 0, y: 0, width: 228, height: Self.collapsedHeight)
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenNone]

        buttonSurface.frame = rect
        buttonSurface.wantsLayer = true
        buttonSurface.layer?.backgroundColor = NSColor(srgbRed: 0.12, green: 0.36, blue: 0.93, alpha: 1).cgColor
        buttonSurface.layer?.cornerRadius = 14
        buttonSurface.layer?.masksToBounds = true
        contentView = buttonSurface

        launchButton.frame = NSRect(x: 0, y: 0, width: 181, height: Self.collapsedHeight)
        launchButton.keyEquivalent = "\r"
        addControl(launchButton)
        addDivider(frame: NSRect(x: 181, y: 12, width: 1, height: 30))

        optionsButton.frame = NSRect(x: 182, y: 0, width: 46, height: Self.collapsedHeight)
        optionsButton.contentTintColor = .white
        optionsButton.toolTip = "启动选项"
        optionsButton.target = self
        optionsButton.action = #selector(toggleOptions)
        addControl(optionsButton)

        visibleLaunchButton.frame = NSRect(x: 0, y: -Self.optionHeight, width: rect.width, height: Self.optionHeight)
        setTitle("启动astrbot（不隐藏）", on: visibleLaunchButton, size: 16)
        addControl(visibleLaunchButton)
        addDivider(frame: NSRect(x: 15, y: -1, width: rect.width - 30, height: 1))
        visibleLaunchButton.isHidden = true
        updateChevron()
        setStarting(false)
        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func addControl(_ button: NSButton) {
        button.isBordered = false
        button.focusRingType = .none
        button.autoresizingMask = [.minYMargin]
        buttonSurface.addSubview(button)
    }

    private func addDivider(frame: NSRect) {
        let divider = NSView(frame: frame)
        divider.autoresizingMask = [.minYMargin]
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.30).cgColor
        buttonSurface.addSubview(divider)
    }

    private func setTitle(_ title: String, on button: NSButton, size: CGFloat) {
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white
        ])
        button.setAccessibilityLabel(title)
    }

    private func updateChevron() {
        optionsButton.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        optionsButton.setAccessibilityLabel(expanded ? "收起启动选项" : "展开启动选项")
    }

    @objc private func toggleOptions() { setExpanded(!expanded, animate: true) }

    func collapseOptions() { setExpanded(false, animate: false) }

    override func cancelOperation(_ sender: Any?) { collapseOptions() }

    override func resignKey() {
        super.resignKey()
        collapseOptions()
    }

    private func setExpanded(_ expanded: Bool, animate: Bool) {
        guard self.expanded != expanded else { return }
        self.expanded = expanded
        updateChevron()
        if expanded { visibleLaunchButton.isHidden = false }
        if !expanded && firstResponder === visibleLaunchButton { makeFirstResponder(optionsButton) }
        let height = Self.collapsedHeight + (expanded ? Self.optionHeight : 0)
        let target = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        setFrame(target, display: true, animate: animate && isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        visibleLaunchButton.isHidden = !expanded
        invalidateShadow()
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.16 }

    func setStarting(_ starting: Bool) {
        if starting { collapseOptions() }
        setTitle(starting ? "正在启动…" : "运行astrbot", on: launchButton, size: 18)
        launchButton.isEnabled = !starting
        optionsButton.isEnabled = !starting
        visibleLaunchButton.isEnabled = !starting
    }
}
