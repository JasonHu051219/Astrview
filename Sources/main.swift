import AppKit

let app = NSApplication.shared
let delegate = AstrviewApp()
delegate.applyDockPreference()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
