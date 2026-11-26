import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AstrviewApp()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
