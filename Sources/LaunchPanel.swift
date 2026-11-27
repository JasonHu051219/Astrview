import AppKit

final class LaunchPanel: NSPanel {
    let launchButton = NSButton(title: "运行astrbot", target: nil, action: nil)
    let settingsButton = NSButton(title: "", target: nil, action: nil)
    let hideCheckbox = NSButton(checkboxWithTitle: "启动后隐藏", target: nil, action: nil)
    var hidesAfterLaunch: Bool { hideCheckbox.state == .on }

    init() {
        let rect = NSRect(x: 0, y: 0, width: 282, height: 129)
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenNone]

        let card = NSVisualEffectView(frame: rect)
        card.appearance = NSAppearance(named: .darkAqua)
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 22
        card.layer?.masksToBounds = true
        contentView = card

        let buttonSurface = NSView(frame: NSRect(x: 21, y: 54, width: 240, height: 54))
        buttonSurface.wantsLayer = true
        buttonSurface.layer?.backgroundColor = NSColor(srgbRed: 0.12, green: 0.36, blue: 0.93, alpha: 1).cgColor
        buttonSurface.layer?.cornerRadius = 14
        buttonSurface.layer?.masksToBounds = true
        card.addSubview(buttonSurface)

        launchButton.frame = NSRect(x: 0, y: 0, width: 191, height: 54)
        launchButton.keyEquivalent = "\r"
        settingsButton.frame = NSRect(x: 192, y: 0, width: 48, height: 54)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium))
        settingsButton.imagePosition = .imageOnly
        settingsButton.contentTintColor = .white
        settingsButton.setAccessibilityLabel("设置")
        settingsButton.toolTip = "设置"
        for button in [launchButton, settingsButton] {
            button.isBordered = false
            button.focusRingType = .none
            buttonSurface.addSubview(button)
        }
        let divider = NSView(frame: NSRect(x: 191, y: 12, width: 1, height: 30))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.30).cgColor
        buttonSurface.addSubview(divider)

        hideCheckbox.state = .on
        hideCheckbox.sizeToFit()
        hideCheckbox.setFrameOrigin(NSPoint(x: (rect.width - hideCheckbox.frame.width) / 2, y: 19))
        card.addSubview(hideCheckbox)
        launchButton.nextKeyView = settingsButton
        settingsButton.nextKeyView = hideCheckbox
        hideCheckbox.nextKeyView = launchButton
        setStarting(false)
        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setStarting(_ starting: Bool) {
        let title = starting ? "正在启动…" : "运行astrbot"
        launchButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white
        ])
        launchButton.setAccessibilityLabel(title)
        launchButton.isEnabled = !starting
        settingsButton.isEnabled = !starting
        hideCheckbox.isEnabled = !starting
    }
}
