import Cocoa
import Foundation
import SwiftUI
import UserNotifications

class AppController: NSObject, NSApplicationDelegate, ShuttleDeviceDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {

    var statusItem: NSStatusItem!
    var shuttleDevice: ShuttleDevice!
    var config: ShuttleConfig!
    var configPath: URL!

    // State
    var activeProfile: ShuttleProfile?
    var currentAppName: String = ""
    var isEnabled: Bool = true
    var lastButtonMask: UInt32 = 0
    var lastJogVal: Int?

    // Shuttle Logic
    var shuttleValue: Int = 0
    var shuttleTimer: Timer?
    var isTransitioning: Bool = false
    var targetPeriod: Double = 0

    // Startup Buffer Logic
    var isStartupPending: Bool = false
    var startupCheckTime: TimeInterval = 0
    let STARTUP_DELAY: TimeInterval = 0.08

    // UI
    var connectionStatusItem: NSMenuItem!
    var appStatusItem: NSMenuItem!
    var profileStatusItem: NSMenuItem!
    var buttonMenuItems: [NSMenuItem] = []
    // Correcting target content to match line 35.
    var speedMenuItems: [NSMenuItem] = []

    var settingsWindow: NSWindow?
    private var settingsStore: Any?

    // Assets
    var iconActive: NSImage?
    var iconInactive: NSImage?
    var iconDisconnected: NSImage?

    func checkAccessibilityPermissions() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !isTrusted {
            print("Accessibility permissions not granted. Prompting user...")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "輔助使用權限已重置 (Accessibility Required)"
                alert.informativeText = "為了讓 MacShuttle 模擬按鍵與滾動，請在「系統設定 > 安全性與隱私權 > 輔助使用」中勾選 MacShuttle。\n\n由於每次 Build 都會更換簽署身分，如果你已看到 MacShuttle 在清單中，請先「取消勾選再重新勾選」即可生效。"
                alert.addButton(withTitle: "開啟系統設定 (Open Settings)")
                alert.addButton(withTitle: "稍後再說 (Later)")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            print("Accessibility permissions granted.")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check Accessibility Permissions
        checkAccessibilityPermissions()

        // Setup Config Path in Application Support
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupportURL.appendingPathComponent("MacShuttle")

            // Create directory if it doesn't exist
            do {
                try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating Application Support directory: \(error)")
            }

            configPath = appDir.appendingPathComponent("shuttle_config.json")
            print("Config path: \(configPath.path)")
        } else {
            // Fallback
            configPath = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("shuttle_config.json")
        }

        // Load Assets
        // Try Bundle resources first
        if let active = Bundle.main.image(forResource: "icon-active-Template"),
           let inactive = Bundle.main.image(forResource: "icon-inactive-Template"),
           let disconnected = Bundle.main.image(forResource: "icon-disconnected-Template") {
            iconActive = active
            iconInactive = inactive
            iconDisconnected = disconnected
        } else {
            // Fallback to local 'assets' folder (legacy mode)
             let fileManager = FileManager.default
             let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
             let assetsDir = currentDir.appendingPathComponent("assets")

            iconActive = NSImage(contentsOf: assetsDir.appendingPathComponent("icon-active-Template.png"))
            iconInactive = NSImage(contentsOf: assetsDir.appendingPathComponent("icon-inactive-Template.png"))
            iconDisconnected = NSImage(contentsOf: assetsDir.appendingPathComponent("icon-disconnected-Template.png"))
        }

        // Resize to standard Menu Bar size
        let iconSize = NSSize(width: 18, height: 18)
        iconActive?.size = iconSize
        iconInactive?.size = iconSize
        iconDisconnected?.size = iconSize

        // Ensure Icons are template
        iconActive?.isTemplate = true
        iconInactive?.isTemplate = true
        iconDisconnected?.isTemplate = true

        // Setup Notifications
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    self.showNotification(title: "MacShuttle", message: "應用程式已啟動 (Notification Test)")
                }
            }
        }

        // Load Config
        loadConfig()

        // Setup Menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(connected: false)
        buildMenu()

        // Setup HID
        shuttleDevice = ShuttleDevice()
        shuttleDevice.delegate = self

        // Watch active app
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // Initial app check
        if let app = NSWorkspace.shared.frontmostApplication {
            currentAppName = app.localizedName ?? "Unknown"
            updateActiveProfile()
        }

        print("MacShuttle Swift Started")
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    // MARK: - Config

    func loadConfig() {
        do {
            if FileManager.default.fileExists(atPath: configPath.path) {
                let data = try Data(contentsOf: configPath)
                config = try JSONDecoder().decode(ShuttleConfig.self, from: data)
            } else {
                config = defaultConfig
                saveConfig()
            }
        } catch {
            print("Config error: \(error)")
            config = defaultConfig
        }
    }

    func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configPath)
        } catch {
            print("Save error: \(error)")
        }
    }

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        connectionStatusItem = NSMenuItem(title: "狀態: 未連接", action: nil, keyEquivalent: "")
        menu.addItem(connectionStatusItem)

        appStatusItem = NSMenuItem(title: "當前 App: \(currentAppName)", action: nil, keyEquivalent: "")
        menu.addItem(appStatusItem)

        profileStatusItem = NSMenuItem(title: "使用設定: 無", action: nil, keyEquivalent: "")
        menu.addItem(profileStatusItem)

        menu.addItem(NSMenuItem.separator())

        let enableItem = NSMenuItem(title: "啟用中 (Enabled)", action: #selector(toggleEnabled(_:)), keyEquivalent: "e")
        enableItem.state = isEnabled ? .on : .off
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "偏好設定... (Preferences)", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let openJsonItem = NSMenuItem(title: "編輯設定檔 (shuttle_config.json)", action: #selector(openJson), keyEquivalent: "")
        openJsonItem.target = self
        menu.addItem(openJsonItem)

        let reloadItem = NSMenuItem(title: "重新載入設定檔", action: #selector(manualReload), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "離開 (Quit)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuState()
    }

    func updateMenuState() {
        appStatusItem.title = "當前 App: \(currentAppName)"

        if let profile = activeProfile {
            profileStatusItem.title = "使用設定: \(profile.name)"
        } else {
            profileStatusItem.title = "使用設定: 無 (未匹配)"
        }
    }

    func updateIcon(connected: Bool) {
        if !connected {
            statusItem.button?.image = iconDisconnected
            if iconDisconnected == nil { statusItem.button?.title = "⚠️" }
        } else if !isEnabled {
            statusItem.button?.image = iconInactive
            if iconInactive == nil { statusItem.button?.title = "⚪" }
        } else {
            statusItem.button?.image = iconActive
            if iconActive == nil { statusItem.button?.title = "🎛️" }
        }
    }

    // MARK: - Actions

    @objc func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        let isConnected = connectionStatusItem.title.contains("已連接")
        updateIcon(connected: isConnected)
    }

    @objc func manualReload() {
        loadConfig()
        updateActiveProfile()
        updateMenuState()
        showNotification(title: "MacShuttle", message: "設定已更新")
    }

    @objc func openJson() {
        NSWorkspace.shared.open(configPath)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let store = SettingsStore(config: self.config, onSave: { [weak self] newConfig in
            self?.config = newConfig
            self?.saveConfig()
            self?.updateActiveProfile()
            self?.updateMenuState()
        })
        self.settingsStore = store

        let contentView = SettingsView(store: store)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.setContentSize(NSSize(width: 800, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Handle window close to clean up
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
            self?.settingsWindow = nil
            self?.settingsStore = nil
        }
    }

    // MARK: - Dialogs & Editing

    func showInputDialog(title: String, message: String, defaultValue: String) -> String? {
        // Activate app to bring alert to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input

        // Ensure input field gets focus
        alert.window.initialFirstResponder = input

        print("Displaying dialog: \(title)")
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            return input.stringValue
        }
        return nil
    }

    func showConfirmationDialog(title: String, message: String) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "建立")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    func createNewProfileForCurrentApp() -> ShuttleProfile? {
        if currentAppName.isEmpty || currentAppName == "Unknown" {
            let _ = showInputDialog(title: "錯誤", message: "無法識別當前應用程式", defaultValue: "")
            return nil
        }

        // Use default speeds
        let newProfile = ShuttleProfile(
            name: currentAppName,
            apps: [currentAppName],
            speeds: [800, 600, 333, 200, 100, 50, 20],
            buttons: [:]
        )

        // Insert at beginning
        config.profiles.insert(newProfile, at: 0)
        saveConfig()
        loadConfig()
        updateActiveProfile()

        showNotification(title: "MacShuttle", message: "設定檔建立成功: \(currentAppName)")
        return activeProfile
    }

    @objc func uiSetApps() {
        var profile = activeProfile

        if profile == nil {
            if showConfirmationDialog(title: "建立設定檔", message: "目前應用程式 '\(currentAppName)' 沒有對應的設定檔。\n是否要為此 App 建立一個新的設定檔？") {
                profile = createNewProfileForCurrentApp()
            }
        }

        guard let p = profile else { return }

        print("Setting Apps for profile: \(p.name)")
        let current = p.apps.joined(separator: ",")
        if let newVal = showInputDialog(title: "設定 App (\(p.name))", message: "請輸入目標 App 名稱 (以逗號分隔)", defaultValue: current) {
            let newApps = newVal.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            if let idx = config.profiles.firstIndex(where: { $0.name == p.name }) {
                config.profiles[idx].apps = newApps
                saveConfig()
                loadConfig()
                updateActiveProfile()
                showNotification(title: "MacShuttle", message: "App 清單已更新")
            }
        }
    }

    @objc func uiSetButton(_ sender: NSMenuItem) {
        print("uiSetButton clicked for tag: \(sender.tag)")

        var profile = activeProfile

        if profile == nil {
             if showConfirmationDialog(title: "建立設定檔", message: "目前應用程式 '\(currentAppName)' 沒有對應的設定檔。\n是否要為此 App 建立一個新的設定檔？") {
                profile = createNewProfileForCurrentApp()
            }
        }

        guard let p = profile else { return }

        let btnId = String(sender.tag)
        let current = p.buttons[btnId] ?? ""

        if let newVal = showInputDialog(title: "設定 Button \(btnId)", message: "請輸入按鍵 (例如: q, enter, command+c)\n留空則清除。", defaultValue: current) {
            if let idx = config.profiles.firstIndex(where: { $0.name == p.name }) {
                if newVal.isEmpty {
                    config.profiles[idx].buttons.removeValue(forKey: btnId)
                } else {
                    config.profiles[idx].buttons[btnId] = newVal
                }
                saveConfig()
                loadConfig()
                updateActiveProfile()
                updateMenuState()
                showNotification(title: "MacShuttle", message: "Button \(btnId) 已更新")
            }
        }
    }

    @objc func uiSetSpeed(_ sender: NSMenuItem) {
        var profile = activeProfile

        if profile == nil {
             if showConfirmationDialog(title: "建立設定檔", message: "目前應用程式 '\(currentAppName)' 沒有對應的設定檔。\n是否要為此 App 建立一個新的設定檔？") {
                profile = createNewProfileForCurrentApp()
            }
        }

        guard let p = profile else { return }

        let idx = sender.tag
        let current = String(p.speeds[idx])

        if let newVal = showInputDialog(title: "設定速度 Level \(idx+1)", message: "請輸入毫秒數", defaultValue: current),
           let val = Int(newVal) {
             if let pIdx = config.profiles.firstIndex(where: { $0.name == p.name }) {
                 config.profiles[pIdx].speeds[idx] = val
                 saveConfig()
                 loadConfig()
                 updateActiveProfile()
                 updateMenuState()
                 showNotification(title: "MacShuttle", message: "速度已更新")
             }
        }
    }

    // MARK: - Logic

    @objc func appChanged(_ notif: Notification) {
        if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let name = app.localizedName ?? "Unknown"

            // Ignore system stuff and self
            let selfName = ProcessInfo.processInfo.processName
            if ["System Events", "loginwindow", "Control Center", "Notification Center", selfName, "MacShuttle", "MacShuttleNative"].contains(name) { return }

            if name != currentAppName {
                currentAppName = name
                shuttleValue = 0 // Reset shuttle
                shuttleTimer?.invalidate()
                shuttleTimer = nil
                updateActiveProfile()
                updateMenuState()
            }
        }
    }

    func updateActiveProfile() {
        var matched: ShuttleProfile? = nil

        // Exact match
        for p in config.profiles {
            if p.apps.contains("*") { continue }
            // Strict match to avoid "2" matching "iTerm2"
            if p.apps.contains(where: { currentAppName.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
                matched = p
                break
            }
        }

        // Fallback default
        if matched == nil {
            for p in config.profiles {
                if p.apps.contains("*") {
                    matched = p
                    break
                }
            }
        }

        activeProfile = matched
    }

    // MARK: - Device Delegate

    func shuttleDeviceDidConnect(_ device: ShuttleDevice) {
        DispatchQueue.main.async {
            self.connectionStatusItem.title = "已連接: ShuttleXpress/Pro"
            self.updateIcon(connected: true)
        }
    }

    func shuttleDeviceDidDisconnect(_ device: ShuttleDevice) {
        DispatchQueue.main.async {
            self.connectionStatusItem.title = "狀態: 未連接"
            self.updateIcon(connected: false)
        }
    }

    func shuttleDevice(_ device: ShuttleDevice, didUpdateButtons mask: UInt32) {
        guard isEnabled, let profile = activeProfile else { return }

        let pressed = mask & ~lastButtonMask
        lastButtonMask = mask

        if pressed == 0 { return }

        for i in 0..<16 {
            if (pressed >> i) & 1 == 1 {
                let btnId = String(i + 1)
                if let action = profile.buttons[btnId] {
                    InputController.shared.performKey(keyDef: action)
                }
            }
        }
    }

    func shuttleDevice(_ device: ShuttleDevice, didUpdateJog value: Int) {
        guard isEnabled else { return }

        if let last = lastJogVal {
            var diff = value - last
            if diff > 127 { diff -= 256 }
            else if diff < -127 { diff += 256 }

            if diff != 0 {
                let direction = diff > 0 ? 1 : -1
                let steps = abs(diff)
                for _ in 0..<steps {
                    InputController.shared.performScroll(direction: direction, multiplier: 3)
                }
            }
        }
        lastJogVal = value
    }

    func shuttleDevice(_ device: ShuttleDevice, didUpdateShuttle value: Int) {
        guard isEnabled else { return }

        // Logic from Python "HandleShuttle"
        if value != shuttleValue {
            // Change detected

            if value == 0 {
                // Stop
                shuttleValue = 0
                shuttleTimer?.invalidate()
                shuttleTimer = nil
                isTransitioning = false
                isStartupPending = false
                return
            }

            // Startup Buffer
            if isStartupPending {
                // Still in pending, just update target
                shuttleValue = value
                return
            }

            if shuttleValue == 0 {
                // Starting from 0
                isStartupPending = true
                shuttleValue = value

                DispatchQueue.main.asyncAfter(deadline: .now() + STARTUP_DELAY) {
                    self.executeStartup()
                }
                return
            }

            // Transition logic (changing speed while moving)
            isTransitioning = false
            let newPeriod = getPeriod(speed: value)
            let oldPeriod = getPeriod(speed: shuttleValue)
            var waitDelay: Double = 0

            if abs(value) > abs(shuttleValue) {
                waitDelay = abs(oldPeriod - newPeriod) / 2.0
            } else if abs(value) < abs(shuttleValue) {
                waitDelay = (oldPeriod + newPeriod) / 2.0
            }

            shuttleValue = value

            // Re-schedule
            shuttleTimer?.invalidate()

            if waitDelay < 0.04 {
                // Instant
                performScrollAction()
                startScrollTimer(interval: newPeriod)
            } else {
                isTransitioning = true
                targetPeriod = newPeriod
                shuttleTimer = Timer.scheduledTimer(withTimeInterval: waitDelay, repeats: false) { _ in
                    self.performScrollAction()
                    self.startScrollTimer(interval: self.targetPeriod)
                    self.isTransitioning = false
                }
            }

        }
    }

    func executeStartup() {
        isStartupPending = false
        if shuttleValue == 0 { return }

        let period = getPeriod(speed: shuttleValue)
        performScrollAction()
        startScrollTimer(interval: period)
        isTransitioning = false
    }

    func startScrollTimer(interval: Double) {
        shuttleTimer?.invalidate()
        shuttleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.performScrollAction()
        }
    }

    func performScrollAction() {
        if shuttleValue == 0 { return }
        let direction = shuttleValue > 0 ? 1 : -1
        InputController.shared.performScroll(direction: direction, multiplier: 2)
    }

    func getPeriod(speed: Int) -> Double {
        guard let profile = activeProfile else { return 0.1 }
        let idx = min(max(abs(speed) - 1, 0), 6)
        // Safety check for index
        if idx < profile.speeds.count {
            return Double(profile.speeds[idx]) / 1000.0
        }
        return 0.1
    }
}