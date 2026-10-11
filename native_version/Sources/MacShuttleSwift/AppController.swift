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
    var currentBundleId: String = ""
    var isEnabled: Bool = true
    var lastButtonMask: UInt32 = 0
    var lastJogVal: Int?

    // Shuttle Scroll Engine
    let scrollEngine = ShuttleScrollEngine()

    // UI
    var connectionStatusItem: NSMenuItem!
    var appStatusItem: NSMenuItem!
    var profileStatusItem: NSMenuItem!


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
            currentBundleId = app.bundleIdentifier ?? ""
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

    // MARK: - Config Save Queue & Debounce

    private let configSaveQueue = DispatchQueue(label: "com.macshuttle.configSaveQueue", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var saveSequence: Int = 0

    func loadConfig() {
        do {
            if FileManager.default.fileExists(atPath: configPath.path) {
                let data = try Data(contentsOf: configPath)
                config = try JSONDecoder().decode(ShuttleConfig.self, from: data)
            } else {
                config = defaultConfig
                saveConfig(debounce: false)
            }
        } catch {
            print("Config error: \(error)")
            config = defaultConfig
        }
    }

    func saveConfig(debounce: Bool = true, delay: TimeInterval = 0.5) {
        pendingSaveWorkItem?.cancel()

        guard let currentConfig = self.config, let path = self.configPath else { return }

        saveSequence += 1
        let currentSeq = saveSequence

        let workItem = DispatchWorkItem { [weak self] in
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(currentConfig)
                try data.write(to: path, options: .atomic)
            } catch {
                print("Save error: \(error)")
            }
            DispatchQueue.main.async {
                if self?.saveSequence == currentSeq {
                    self?.pendingSaveWorkItem = nil
                }
            }
        }

        pendingSaveWorkItem = workItem

        if debounce {
            configSaveQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            configSaveQueue.async(execute: workItem)
        }
    }

    func flushPendingSave() {
        guard let item = pendingSaveWorkItem, !item.isCancelled else { return }
        item.cancel()
        pendingSaveWorkItem = nil

        guard let currentConfig = self.config, let path = self.configPath else { return }
        configSaveQueue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(currentConfig)
                try data.write(to: path, options: .atomic)
            } catch {
                print("Flush save error: \(error)")
            }
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
        appStatusItem.toolTip = currentBundleId.isEmpty ? nil : "Bundle ID: \(currentBundleId)"

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
        if !isEnabled {
            scrollEngine.stop()
        }
        sender.state = isEnabled ? .on : .off
        let isConnected = connectionStatusItem.title.contains("已連接")
        updateIcon(connected: isConnected)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        scrollEngine.stop()
        flushPendingSave()
    }

    @objc func manualReload() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        loadConfig()
        updateActiveProfile()
        updateMenuState()
        showNotification(title: "MacShuttle", message: "設定已更新")
    }

    @objc func openJson() {
        NSWorkspace.shared.open(configPath)
    }

    @objc func quitApp() {
        flushPendingSave()
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
            self?.flushPendingSave()
            self?.settingsWindow = nil
            self?.settingsStore = nil
        }
    }


    // MARK: - Logic

    @objc func appChanged(_ notif: Notification) {
        if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let name = app.localizedName ?? "Unknown"
            let bundleId = app.bundleIdentifier ?? ""

            // Ignore system stuff and self
            let selfName = ProcessInfo.processInfo.processName
            let selfBundleId = Bundle.main.bundleIdentifier ?? ""
            if ["System Events", "loginwindow", "Control Center", "Notification Center", selfName, "MacShuttle", "MacShuttleNative"].contains(name) ||
               (!selfBundleId.isEmpty && bundleId == selfBundleId) { return }

            if name != currentAppName || bundleId != currentBundleId {
                currentAppName = name
                currentBundleId = bundleId
                scrollEngine.reset()
                updateActiveProfile()
                updateMenuState()
            }
        }
    }

    func updateActiveProfile() {
        var matched: ShuttleProfile? = nil

        // Exact match by localizedName or bundleIdentifier
        for p in config.profiles {
            if p.apps.contains("*") { continue }
            // Strict match against localizedName or bundleIdentifier
            if p.apps.contains(where: { target in
                target.localizedCaseInsensitiveCompare(currentAppName) == .orderedSame ||
                (!currentBundleId.isEmpty && target.localizedCaseInsensitiveCompare(currentBundleId) == .orderedSame)
            }) {
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
        scrollEngine.speeds = matched?.speeds ?? defaultSpeeds
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
        guard isEnabled else {
            scrollEngine.stop()
            return
        }
        scrollEngine.updateShuttle(value: value)
    }
}