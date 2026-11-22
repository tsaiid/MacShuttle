import SwiftUI
import Combine

enum ProfileTab: Hashable {
    case targetApps
    case buttons
    case jogAndShuttle
}

class SettingsStore: ObservableObject {
    @Published var config: ShuttleConfig
    @Published var selectedProfileId: UUID?
    var onSave: (ShuttleConfig) -> Void

    init(config: ShuttleConfig, selectedProfileId: UUID? = nil, onSave: @escaping (ShuttleConfig) -> Void) {
        self.config = config
        self.selectedProfileId = selectedProfileId ?? config.profiles.first?.id
        self.onSave = onSave
    }

    func save() {
        onSave(config)
    }

    func profile(for id: UUID) -> ShuttleProfile? {
        config.profiles.first(where: { $0.id == id })
    }

    func binding(for profileId: UUID, fallback: ShuttleProfile) -> Binding<ShuttleProfile> {
        Binding(
            get: { [weak self] in
                self?.config.profiles.first(where: { $0.id == profileId }) ?? fallback
            },
            set: { [weak self] newValue in
                guard let self = self,
                      let index = self.config.profiles.firstIndex(where: { $0.id == profileId }) else {
                    return
                }
                self.config.profiles[index] = newValue
            }
        )
    }

    func addProfile() {
        let newProfile = ShuttleProfile(
            name: "New Profile \(config.profiles.count + 1)",
            apps: [],
            speeds: defaultSpeeds,
            buttons: [:]
        )
        config.profiles.insert(newProfile, at: 0)
        selectedProfileId = newProfile.id
        save()
    }

    func deleteSelectedProfile() {
        guard let id = selectedProfileId,
              let index = config.profiles.firstIndex(where: { $0.id == id }) else { return }

        var updatedProfiles = config.profiles
        updatedProfiles.remove(at: index)
        let nextSelection: UUID? = updatedProfiles.isEmpty
            ? nil
            : updatedProfiles[min(index, updatedProfiles.count - 1)].id

        selectedProfileId = nextSelection
        config.profiles = updatedProfiles
        save()
    }

    func addApp(_ raw: String, to profileId: UUID) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = config.profiles.firstIndex(where: { $0.id == profileId }) else { return }

        if !config.profiles[index].apps.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            config.profiles[index].apps.append(trimmed)
            save()
        }
    }

    func moveApp(_ raw: String, to targetProfileId: UUID, aliases: [AppAlias] = []) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let targetIndex = config.profiles.firstIndex(where: { $0.id == targetProfileId }) else { return }

        var updatedProfiles = config.profiles
        for i in updatedProfiles.indices where updatedProfiles[i].id != targetProfileId {
            updatedProfiles[i].apps.removeAll { entry in
                ProfileConflictDetector.entriesMatch(trimmed, entry, aliases: aliases).matched
            }
        }

        if !updatedProfiles[targetIndex].apps.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            updatedProfiles[targetIndex].apps.append(trimmed)
        }

        config.profiles = updatedProfiles
        save()
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var showDeleteAlert = false
    @State private var selectedTab: ProfileTab = .targetApps

    var body: some View {
        let aliases = ProfileConflictDetector.runningAppAliases()
        NavigationView {
            VStack(spacing: 0) {
                List(selection: $store.selectedProfileId) {
                    ForEach(store.config.profiles) { profile in
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .lineLimit(1)
                            Spacer()
                            if ProfileConflictDetector.profileHasWarnings(
                                profileId: profile.id,
                                profiles: store.config.profiles,
                                aliases: aliases
                            ) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                    .help("此設定檔有 App 重疊或規則衝突")
                            }
                        }
                        .tag(profile.id)
                    }
                    .onMove { indices, newOffset in
                        store.config.profiles.move(fromOffsets: indices, toOffset: newOffset)
                        store.save()
                    }
                }
                .listStyle(SidebarListStyle())

                Text("優先順序由上而下，可拖曳調整")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                Divider()

                HStack(spacing: 12) {
                    // App Icon & Version
                    HStack(spacing: 8) {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                        }
                        Text("v\(AppVersion.shortVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { store.addProfile() }) {
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
                    .disabled(store.selectedProfileId == nil)
                    .help("Remove Profile")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .frame(minWidth: 200)

            if let selectedId = store.selectedProfileId,
               let selectedProfile = store.profile(for: selectedId) {
                ProfileDetailView(
                    store: store,
                    profile: store.binding(for: selectedId, fallback: selectedProfile),
                    selectedTab: $selectedTab,
                    onSave: {
                        store.save()
                    }
                )
                .id(selectedId)
            } else {
                Text("Select a profile to edit")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 700)
        .onAppear {
            if store.config.profiles.isEmpty {
                let defaultProfile = ShuttleProfile(
                    name: "Default (Global)",
                    apps: ["*"],
                    speeds: defaultSpeeds,
                    buttons: [:]
                )
                store.config.profiles.append(defaultProfile)
                store.save()
            }

            if store.selectedProfileId == nil, let first = store.config.profiles.first {
                store.selectedProfileId = first.id
            }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Remove Profile"),
                message: Text("Are you sure you want to remove the selected profile?"),
                primaryButton: .destructive(Text("Remove")) {
                    store.deleteSelectedProfile()
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct ProfileDetailView: View {
    @ObservedObject var store: SettingsStore
    @Binding var profile: ShuttleProfile
    @Binding var selectedTab: ProfileTab
    var onSave: () -> Void
    @State private var newApp: String = ""
    @State private var editingName: String
    @State private var syncedProfileId: UUID
    @FocusState private var isNameFocused: Bool

    init(store: SettingsStore, profile: Binding<ShuttleProfile>, selectedTab: Binding<ProfileTab>, onSave: @escaping () -> Void) {
        self.store = store
        self._profile = profile
        self._selectedTab = selectedTab
        self.onSave = onSave
        let initial = profile.wrappedValue
        self._editingName = State(initialValue: initial.name)
        self._syncedProfileId = State(initialValue: initial.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profile Name:")
                    .foregroundColor(.secondary)
                TextField("Name", text: $editingName)
                    .focused($isNameFocused)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: profile.id) { newId in
                        syncedProfileId = newId
                        editingName = profile.name
                    }
                    .onChange(of: profile.name) { newName in
                        if syncedProfileId == profile.id && !isNameFocused && editingName != newName {
                            editingName = newName
                        }
                    }
                    .onChange(of: editingName) { newValue in
                        guard syncedProfileId == profile.id else { return }
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && profile.name != newValue {
                            profile.name = newValue
                            onSave()
                        }
                    }
                    .onChange(of: isNameFocused) { focused in
                        if !focused {
                            commitProfileName()
                        }
                    }
                    .onSubmit {
                        commitProfileName()
                    }
            }
            .padding()

            Divider()

            TabView(selection: $selectedTab) {
                TargetAppsView(store: store, profile: $profile, onSave: onSave, newApp: $newApp)
                    .tabItem { Text("Target Apps") }
                    .tag(ProfileTab.targetApps)

                ButtonsView(profile: $profile, onSave: onSave)
                    .tabItem { Text("Buttons") }
                    .tag(ProfileTab.buttons)

                JogAndShuttleView(profile: $profile, onSave: onSave)
                    .tabItem { Text("Jog & Shuttle") }
                    .tag(ProfileTab.jogAndShuttle)
            }
            .padding()
        }
    }

    private func commitProfileName() {
        guard syncedProfileId == profile.id else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            editingName = profile.name.isEmpty ? "Untitled Profile" : profile.name
        } else if profile.name != trimmed {
            profile.name = trimmed
            editingName = trimmed
            onSave()
        }
    }
}

private struct PendingAppConflict {
    let appIdentifier: String
    let conflictingProfileNames: [String]
    let clearInputAfterAction: Bool
}

struct TargetAppsView: View {
    @ObservedObject var store: SettingsStore
    @Binding var profile: ShuttleProfile
    var onSave: () -> Void
    @Binding var newApp: String
    @State private var pendingConflict: PendingAppConflict?
    @State private var showConflictAlert: Bool = false

    private var runningApps: [(name: String, identifier: String)] {
        let selfBundleId = Bundle.main.bundleIdentifier ?? ""
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, identifier: String)? in
                let name = app.localizedName ?? ""
                let bundleId = app.bundleIdentifier ?? ""
                if !selfBundleId.isEmpty && bundleId == selfBundleId { return nil }
                let identifier = bundleId.isEmpty ? name : bundleId
                guard !identifier.isEmpty else { return nil }
                return (name: name.isEmpty ? identifier : name, identifier: identifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let aliases = ProfileConflictDetector.runningAppAliases()

        VStack(alignment: .leading, spacing: 10) {
            Text("Target Application Names or Bundle IDs (case-insensitive)")
                .font(.caption)
                .foregroundColor(.secondary)

            if ProfileConflictDetector.hasMixedWildcard(in: profile) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                        .padding(.top, 1)
                    Text("此設定檔同時包含萬用字元 `*` 與特定 App，系統會將整個設定檔視為全域預設（Global Fallback），其他特定 App 不會在第一輪被優先比對。")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            List {
                ForEach(profile.apps, id: \.self) { app in
                    let overlaps = ProfileConflictDetector.overlaps(
                        for: app,
                        in: profile.id,
                        profiles: store.config.profiles,
                        aliases: aliases
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(app)
                            Spacer()
                            Button(action: {
                                removeApp(app)
                            }) {
                                Image(nsImage: NSImage(named: NSImage.stopProgressTemplateName)!)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Remove App")
                        }

                        ForEach(overlaps) { info in
                            HStack(spacing: 4) {
                                Image(systemName: info.isWarning ? "exclamationmark.triangle.fill" : "info.circle")
                                    .font(.system(size: 10))
                                Text(overlapMessage(for: info))
                                    .font(.caption2)
                            }
                            .foregroundColor(info.isWarning ? .orange : .secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .border(Color(NSColor.separatorColor), width: 1)

            HStack {
                TextField("Add App or Bundle ID (e.g. Chrome, com.google.Chrome)", text: $newApp, onCommit: {
                    addApp(newApp, fromInputField: true)
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addApp(newApp, fromInputField: true)
                }

                Menu("從執行中程式加入") {
                    ForEach(runningApps, id: \.identifier) { item in
                        Button("\(item.name) (\(item.identifier))") {
                            addApp(item.identifier)
                        }
                    }
                }

                Button("瀏覽...") {
                    browseApplication()
                }
            }

            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { profile.hoverPriority },
                set: {
                    profile.hoverPriority = $0
                    onSave()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("滑鼠懸停優先 (Hover Priority)")
                        .font(.system(size: 13, weight: .medium))
                    Text("雙螢幕游標停在此 App 視窗上時自動套用此設定檔，並在按鍵前自動聚焦目標視窗")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(profile.apps.contains("*"))
        }
        .padding()
        .alert(
            "應用程式已在其他設定檔中",
            isPresented: $showConflictAlert,
            presenting: pendingConflict
        ) { conflict in
            Button("移動至此設定檔") {
                let aliases = ProfileConflictDetector.runningAppAliases()
                store.moveApp(conflict.appIdentifier, to: profile.id, aliases: aliases)
                if conflict.clearInputAfterAction {
                    newApp = ""
                }
                pendingConflict = nil
            }
            Button("兩邊都保留") {
                store.addApp(conflict.appIdentifier, to: profile.id)
                if conflict.clearInputAfterAction {
                    newApp = ""
                }
                pendingConflict = nil
            }
            Button("取消", role: .cancel) {
                pendingConflict = nil
            }
        } message: { conflict in
            let names = conflict.conflictingProfileNames.joined(separator: "、")
            Text("「\(conflict.appIdentifier)」已出現在其他設定檔（\(names)）中。\n若兩邊都保留，將依左側設定檔由上而下的順序優先套用。")
        }
    }

    private func overlapMessage(for info: AppOverlapInfo) -> String {
        let aliasSuffix = info.isAliasMatch ? "（對應: \(info.matchedEntry)）" : ""
        switch info.kind {
        case .shadowedByHigher:
            return "已被上方的「\(info.otherProfileName)」覆蓋（目前不會生效）\(aliasSuffix)"
        case .shadowedExceptHover:
            return "前景已被上方的「\(info.otherProfileName)」覆蓋，僅游標懸停時由此設定檔生效\(aliasSuffix)"
        case .overriddenOnHoverByLower:
            return "優先於下方的「\(info.otherProfileName)」，但游標懸停時會由對方搶走控制權\(aliasSuffix)"
        case .shadowsLower:
            return "與下方的「\(info.otherProfileName)」重疊（目前以此設定檔優先）\(aliasSuffix)"
        }
    }

    func addApp(_ raw: String, fromInputField: Bool = false) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if profile.apps.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            if fromInputField {
                newApp = ""
            }
            return
        }

        let aliases = ProfileConflictDetector.runningAppAliases()
        let conflicts = ProfileConflictDetector.conflictingProfiles(
            for: trimmed,
            excluding: profile.id,
            profiles: store.config.profiles,
            aliases: aliases
        )

        if !conflicts.isEmpty {
            pendingConflict = PendingAppConflict(
                appIdentifier: trimmed,
                conflictingProfileNames: conflicts.map { $0.profile.name },
                clearInputAfterAction: fromInputField
            )
            showConflictAlert = true
            return
        }

        store.addApp(trimmed, to: profile.id)
        if fromInputField {
            newApp = ""
        }
    }

    func removeApp(_ app: String) {
        if let index = profile.apps.firstIndex(of: app) {
            profile.apps.remove(at: index)
            onSave()
        }
    }

    func browseApplication() {
        let panel = NSOpenPanel()
        panel.title = "選擇應用程式"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                addApp(bundleId)
            } else {
                addApp(url.deletingPathExtension().lastPathComponent)
            }
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
        .onChange(of: profile.id) { _ in
            activeRecordingButtonId = nil
        }
    }
}

struct JogAndShuttleView: View {
    @Binding var profile: ShuttleProfile
    var onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("輪盤輸出模式 (Wheel Actions)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    WheelActionRow(
                        title: "Jog Wheel (內圈)",
                        mode: Binding(
                            get: { profile.jogMode },
                            set: {
                                profile.jogMode = $0
                                onSave()
                            }
                        ),
                        inverted: Binding(
                            get: { profile.jogInvert },
                            set: {
                                profile.jogInvert = $0
                                onSave()
                            }
                        )
                    )

                    WheelActionRow(
                        title: "Shuttle Wheel (外圈)",
                        mode: Binding(
                            get: { profile.shuttleMode },
                            set: {
                                profile.shuttleMode = $0
                                onSave()
                            }
                        ),
                        inverted: Binding(
                            get: { profile.shuttleInvert },
                            set: {
                                profile.shuttleInvert = $0
                                onSave()
                            }
                        )
                    )
                }

                Divider()

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
                            get: { i < profile.speeds.count ? profile.speeds[i] : defaultSpeeds[i] },
                            set: {
                                if i < profile.speeds.count {
                                    profile.speeds[i] = $0
                                    onSave()
                                }
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

struct WheelActionRow: View {
    let title: String
    @Binding var mode: WheelActionMode
    @Binding var inverted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 140, alignment: .leading)

                Picker("", selection: $mode) {
                    ForEach(WheelActionMode.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 180)

                Toggle("反轉方向 (Invert)", isOn: $inverted)
                    .toggleStyle(.checkbox)

                Spacer()
            }

            Text(mode.directionHint(inverted: inverted))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 156)
        }
    }
}

struct SpeedRow: View {
    let level: Int
    @Binding var value: Int
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(level: Int, value: Binding<Int>) {
        self.level = level
        self._value = value
        self._text = State(initialValue: String(max(1, value.wrappedValue)))
    }

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
                    if let intVal = Int(sanitized), intVal >= 1, intVal != value {
                        value = intVal
                    }
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        // When losing focus, ensure value is valid and text is synced
                        if text.isEmpty || (Int(text) ?? 0) < 1 {
                            let safeValue = max(1, value)
                            if value != safeValue {
                                value = safeValue
                            }
                        }
                        text = String(max(1, value))
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
                    let expected = String(value)
                    if text != expected {
                        text = expected
                    }
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
