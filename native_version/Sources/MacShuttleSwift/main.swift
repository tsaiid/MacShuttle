import Cocoa

// Setup the application
let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menu bar app
app.run()
