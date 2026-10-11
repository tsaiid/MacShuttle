import SwiftUI
import Combine

class SettingsStore: ObservableObject {
    @Published var config: ShuttleConfig
    var onSave: (ShuttleConfig) -> Void

    init(config: ShuttleConfig, onSave: @escaping (ShuttleConfig) -> Void) {
        self.config = config
        self.onSave = onSave
    }

    func save() {
        onSave(config)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var selectedProfileId: UUID?
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List(selection: $selectedProfileId) {
                    ForEach(store.config.profiles) { profile in
                        Text(profile.name)
                            .tag(profile.id)
                    }
                    .onMove { indices, newOffset in
                        store.config.profiles.move(fromOffsets: indices, toOffset: newOffset)
                        store.save()
                    }
                }
                .listStyle(SidebarListStyle())

                Divider()

                HStack(spacing: 12) {
                    // App Icon
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    }

                    Spacer()

                    Button(action: addProfile) {
                        Image(nsImage: NSImage(named: NSImage.addTemplateName)!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add Profile")

                    Button(action: { showDeleteAlert = true }) {
                        Image(nsImage: NSImage(named: NSImage.removeTemplateName)!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedProfileId == nil)
                    .help("Remove Profile")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .frame(minWidth: 200)

            if let selectedIndex = store.config.profiles.firstIndex(where: { $0.id == selectedProfileId }) {
                ProfileDetailView(profile: $store.config.profiles[selectedIndex], onSave: {
                    store.save()
                })
            } else {
                Text("Select a profile to edit")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if store.config.profiles.isEmpty {
                let defaultProfile = ShuttleProfile(
                    name: "Default (Global)",
                    apps: [],
                    speeds: [800, 600, 333, 200, 100, 50, 20],
                    buttons: [:]
                )
                store.config.profiles.append(defaultProfile)
                store.save()
            }

            if selectedProfileId == nil, let first = store.config.profiles.first {
                selectedProfileId = first.id
            }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Remove Profile"),
                message: Text("Are you sure you want to remove the selected profile?"),
                primaryButton: .destructive(Text("Remove")) {
                    deleteSelectedProfile()
                },
                secondaryButton: .cancel()
            )
        }
    }

    func addProfile() {
        let newProfile = ShuttleProfile(
            name: "New Profile \(store.config.profiles.count + 1)",
            apps: [],
            speeds: [800, 600, 333, 200, 100, 50, 20],
            buttons: [:]
        )
        store.config.profiles.insert(newProfile, at: 0)
        selectedProfileId = newProfile.id
        store.save()
    }

    func deleteSelectedProfile() {
        guard let id = selectedProfileId,
              let index = store.config.profiles.firstIndex(where: { $0.id == id }) else { return }

        store.config.profiles.remove(at: index)
        selectedProfileId = nil
        store.save()
    }
}

struct ProfileDetailView: View {
    @Binding var profile: ShuttleProfile
    var onSave: () -> Void
    @State private var newApp: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profile Name:")
                    .foregroundColor(.secondary)
                TextField("Name", text: Binding(
                    get: { profile.name },
                    set: { newValue in
                        if !newValue.isEmpty {
                            profile.name = newValue
                            onSave()
                        }
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding()

            Divider()

            TabView {
                TargetAppsView(profile: $profile, onSave: onSave, newApp: $newApp)
                    .tabItem { Text("Target Apps") }

                ButtonsView(profile: $profile, onSave: onSave)
                    .tabItem { Text("Buttons") }

                ShuttleSpeedsView(profile: $profile, onSave: onSave)
                    .tabItem { Text("Shuttle Speeds") }
            }
            .padding()
        }
    }
}

struct TargetAppsView: View {
    @Binding var profile: ShuttleProfile
    var onSave: () -> Void
    @Binding var newApp: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target Application Names or Bundle IDs (case-insensitive)")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(Array(profile.apps.enumerated()), id: \.offset) { index, app in
                    HStack {
                        Text(app)
                        Spacer()
                        Button(action: {
                            removeApp(at: index)
                        }) {
                            Image(nsImage: NSImage(named: NSImage.stopProgressTemplateName)!)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help("Remove App")
                    }
                }
            }
            .border(Color(NSColor.separatorColor), width: 1)

            HStack {
                TextField("Add App or Bundle ID (e.g. Chrome, com.google.Chrome)", text: $newApp, onCommit: {
                    addApp()
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addApp()
                }
            }
        }
        .padding()
    }

    func addApp() {
        let trimmed = newApp.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            profile.apps.append(trimmed)
            newApp = ""
            onSave()
        }
    }

    func removeApp(at index: Int) {
        if index < profile.apps.count {
            profile.apps.remove(at: index)
            onSave()
        }
    }
}

class KeyRecorderModel: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var heldModifiers: NSEvent.ModifierFlags = []
    private var monitor: Any?

    func startRecording(onKeyRecorded: @escaping (String) -> Void) {
        stopRecording()
        isRecording = true
        heldModifiers = []

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                DispatchQueue.main.async {
                    self.heldModifiers = flags
                }
                return event
            } else if event.type == .keyDown {
                let canonical = ShortcutFormatter.canonicalString(keyCode: event.keyCode, modifiers: event.modifierFlags)
                DispatchQueue.main.async {
                    self.stopRecording()
                    onKeyRecorded(canonical)
                }
                return nil
            }
            return event
        }
    }

    func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
        heldModifiers = []
    }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}

struct KeyRecorderButton: View {
    let buttonId: String
    @Binding var value: String
    @Binding var activeRecordingId: String?
    var onSave: () -> Void

    @StateObject private var recorder = KeyRecorderModel()

    var body: some View {
        HStack(spacing: 8) {
            if recorder.isRecording {
                Button(action: {
                    recorder.stopRecording()
                    if activeRecordingId == buttonId {
                        activeRecordingId = nil
                    }
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(recordingText)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minWidth: 150, alignment: .center)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help("點擊以取消錄製")

                Button("取消") {
                    recorder.stopRecording()
                    if activeRecordingId == buttonId {
                        activeRecordingId = nil
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
                Button(action: {
                    activeRecordingId = buttonId
                    recorder.startRecording { recordedKey in
                        value = recordedKey
                        activeRecordingId = nil
                        onSave()
                    }
                }) {
                    Text(value.isEmpty ? "點擊錄製" : ShortcutFormatter.displayString(for: value))
                        .font(.system(size: 13, weight: value.isEmpty ? .regular : .semibold, design: value.isEmpty ? .default : .monospaced))
                        .foregroundColor(value.isEmpty ? .secondary : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minWidth: 120, alignment: .center)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help(value.isEmpty ? "點擊錄製快捷鍵" : "目前綁定: \(value)。點擊重新錄製")

                if !value.isEmpty {
                    Button(action: {
                        value = ""
                        onSave()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("清除按鍵設定")
                }
            }
        }
        .onChange(of: activeRecordingId) { newId in
            if newId != buttonId && recorder.isRecording {
                recorder.stopRecording()
            }
        }
        .onDisappear {
            recorder.stopRecording()
        }
    }

    private var recordingText: String {
        let mods = ShortcutFormatter.modifierDisplayString(modifiers: recorder.heldModifiers)
        if mods.isEmpty {
            return "請按下快捷鍵..."
        } else {
            return "\(mods) ..."
        }
    }
}

struct ButtonsView: View {
    @Binding var profile: ShuttleProfile
    var onSave: () -> Void
    @State private var activeRecordingButtonId: String? = nil

    struct ButtonGroup {
        let range: ClosedRange<Int>
        let title: String
        let subtitle: String
    }

    let groups = [
        ButtonGroup(range: 1...4, title: "頂部第一排 (First Top Row)", subtitle: "Buttons 1 ~ 4"),
        ButtonGroup(range: 5...9, title: "頂部第二排 (Second Top Row)", subtitle: "Buttons 5 ~ 9"),
        ButtonGroup(range: 10...11, title: "左側手掌鍵 (Left Palm Buttons)", subtitle: "Buttons 10 ~ 11"),
        ButtonGroup(range: 12...13, title: "右側手掌鍵 (Right Palm Buttons)", subtitle: "Buttons 12 ~ 13"),
        ButtonGroup(range: 14...15, title: "飛輪兩側鍵 (Wheel Side Buttons)", subtitle: "Buttons 14 ~ 15")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(group.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(group.range, id: \.self) { i in
                            HStack {
                                Text("Button \(i)")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundColor(.secondary)

                                KeyRecorderButton(
                                    buttonId: String(i),
                                    value: Binding(
                                        get: { profile.buttons[String(i)] ?? "" },
                                        set: {
                                            if $0.isEmpty {
                                                profile.buttons.removeValue(forKey: String(i))
                                            } else {
                                                profile.buttons[String(i)] = $0
                                            }
                                            onSave()
                                        }
                                    ),
                                    activeRecordingId: $activeRecordingButtonId,
                                    onSave: onSave
                                )
                                Spacer()
                            }
                        }
                    }
                    Divider()
                }
            }
            .padding()
        }
    }
}

struct ShuttleSpeedsView: View {
    @Binding var profile: ShuttleProfile
    var onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Shuttle Speeds (Transition Delay in ms)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Button("Reset to Defaults") {
                        profile.speeds = defaultSpeeds
                        onSave()
                    }
                }

                ForEach(0..<7, id: \.self) { i in
                    SpeedRow(
                        level: i + 1,
                        value: Binding(
                            get: { profile.speeds[i] },
                            set: {
                                profile.speeds[i] = $0
                                onSave()
                            }
                        )
                    )
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct SpeedRow: View {
    let level: Int
    @Binding var value: Int
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Level \(level)")
                .frame(width: 60, alignment: .leading)

            TextField("ms", text: $text)
                .focused($isFocused)
                .onChange(of: text) { newValue in
                    // Step 1: Filter to only digits
                    var sanitized = newValue.filter { $0.isNumber }

                    // Step 2: Remove leading zeros (e.g., "0123" -> "123", "007" -> "7")
                    while sanitized.count > 1 && sanitized.hasPrefix("0") {
                        sanitized.removeFirst()
                    }

                    // Step 3: If it's just "0", convert to "1" (minimum is 1)
                    if sanitized == "0" {
                        sanitized = "1"
                    }

                    // Step 4: Update text if sanitized is different
                    if sanitized != newValue {
                        text = sanitized
                        return
                    }

                    // Step 5: Sync with the Int binding
                    if let intVal = Int(sanitized), intVal >= 1 {
                        value = intVal
                    }
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        // When losing focus, ensure value is valid and text is synced
                        if text.isEmpty || (Int(text) ?? 0) < 1 {
                            value = max(1, value)
                        }
                        text = String(value)
                    }
                }
                .onChange(of: value) { newValue in
                    // Ensure value is always at least 1
                    let safeValue = max(1, newValue)
                    if safeValue != newValue {
                        value = safeValue
                        return
                    }
                    // Always update text if it doesn't match the value
                    // This handles Reset to Defaults and slider/stepper changes
                    let textValue = Int(text) ?? 0
                    if textValue != safeValue {
                        text = String(safeValue)
                    }
                }
                .onAppear {
                    // Ensure initial value is at least 1
                    if value < 1 {
                        value = 1
                    }
                    text = String(value)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 60)

            Stepper("", value: $value, in: 1...Int.max)
                .labelsHidden()

            Slider(
                value: Binding(
                    get: { Double(max(1, min(value, 1000))) },
                    set: { value = max(1, Int($0)) }
                ),
                in: 1...1000
            )
            .frame(width: 150)
        }
    }
}
