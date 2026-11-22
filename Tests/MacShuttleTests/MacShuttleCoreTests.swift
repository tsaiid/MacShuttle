import XCTest
import AppKit
import SwiftUI
@testable import MacShuttleCore

final class ShortcutFormatterTests: XCTestCase {

    func testParseSimpleAndImplicitShiftKeys() {
        let simple = ShortcutFormatter.parseKeyDefinition("q")
        XCTAssertEqual(simple.baseKey, "q")
        XCTAssertTrue(simple.modifiers.isEmpty)

        let upper = ShortcutFormatter.parseKeyDefinition("Z")
        XCTAssertEqual(upper.baseKey, "z")
        XCTAssertEqual(upper.modifiers, ["shift"])
    }

    func testParsePlusSignVariants() {
        let barePlus = ShortcutFormatter.parseKeyDefinition("+")
        XCTAssertEqual(barePlus.baseKey, "plus")
        XCTAssertTrue(barePlus.modifiers.isEmpty)

        let cmdPlus = ShortcutFormatter.parseKeyDefinition("cmd++")
        XCTAssertEqual(cmdPlus.baseKey, "plus")
        XCTAssertEqual(cmdPlus.modifiers, ["command"])

        let spacedCmdPlus = ShortcutFormatter.parseKeyDefinition("shift + cmd + +")
        XCTAssertEqual(spacedCmdPlus.baseKey, "plus")
        XCTAssertEqual(spacedCmdPlus.modifiers, ["shift", "command"])
    }

    func testParseDuplicateModifiersAreDeduplicatedInCanonicalOrder() {
        let parsed = ShortcutFormatter.parseKeyDefinition("cmd+command+shift+alt+ctrl+c")
        XCTAssertEqual(parsed.baseKey, "c")
        XCTAssertEqual(parsed.modifiers, ["control", "option", "shift", "command"])
    }

    func testNumpadEnterAndFunctionKeysMapping() {
        XCTAssertEqual(ShortcutFormatter.canonicalName(for: 76), "keypadenter")
        XCTAssertEqual(macKeyCodes["keypadenter"], 76)
        XCTAssertEqual(macKeyCodes["numpadenter"], 76)
        XCTAssertEqual(macKeyCodes["enter"], 36)
        XCTAssertEqual(macKeyCodes["return"], 36)
        XCTAssertEqual(ShortcutFormatter.displayString(for: "keypadenter"), "Num Enter")

        XCTAssertEqual(ShortcutFormatter.canonicalName(for: 105), "f13")
        XCTAssertEqual(macKeyCodes["f13"], 105)
        XCTAssertEqual(ShortcutFormatter.canonicalName(for: 90), "f20")
        XCTAssertEqual(macKeyCodes["f20"], 90)
        XCTAssertEqual(ShortcutFormatter.canonicalName(for: 250), "key_250")
    }
}

final class ShuttleScrollEngineTests: XCTestCase {

    func testStartupBufferUsesLatestSpeedAndCancelsOnStop() {
        let engine = ShuttleScrollEngine(speeds: [800, 600, 333, 200, 100, 50, 20])
        engine.startupDelay = 0.05

        var directions: [Int] = []
        engine.onScroll = { dir in
            directions.append(dir)
        }

        engine.updateShuttle(value: 1)
        engine.updateShuttle(value: 3)
        XCTAssertTrue(directions.isEmpty, "Should wait for startupDelay before scrolling")

        let exp = expectation(description: "Startup scroll fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(directions.isEmpty)
        XCTAssertEqual(directions.first, 1)
        XCTAssertEqual(engine.currentSpeed, 3)

        engine.stop()
        XCTAssertEqual(engine.currentSpeed, 0)
    }

    func testZeroCrossingDirectionReversalFiresImmediatelyWithNewDirection() {
        let engine = ShuttleScrollEngine(speeds: [800, 600, 333, 200, 100, 50, 20])
        engine.startupDelay = 0.02

        var directions: [Int] = []
        engine.onScroll = { dir in
            directions.append(dir)
        }

        engine.updateShuttle(value: 4)
        let startupExp = expectation(description: "Initial direction established")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            startupExp.fulfill()
        }
        wait(for: [startupExp], timeout: 1.0)
        XCTAssertTrue(directions.contains(1))

        directions.removeAll()
        engine.updateShuttle(value: -1)

        // Zero-crossing reversal should immediately emit -1 without waiting for oldPeriod+newPeriod/2 (450ms)
        XCTAssertEqual(engine.currentSpeed, -1)
        XCTAssertEqual(directions.first, -1)
        engine.stop()
    }
}

final class ConfigDecodingTests: XCTestCase {

    func testLegacyJsonDecodesWithDefaultsAndNormalizedSpeeds() throws {
        let json = """
        {
          "profiles": [
            {
              "name": "Legacy",
              "apps": ["com.microsoft.rdc.macos"],
              "speeds": [0, -10, 300],
              "buttons": { "1": "q" }
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(ShuttleConfig.self, from: json)
        XCTAssertEqual(config.profiles.count, 1)
        let profile = config.profiles[0]
        XCTAssertEqual(profile.name, "Legacy")
        XCTAssertFalse(profile.hoverPriority)
        XCTAssertEqual(profile.jogMode, .scroll)
        XCTAssertFalse(profile.jogInvert)
        XCTAssertEqual(profile.shuttleMode, .scroll)
        XCTAssertFalse(profile.shuttleInvert)
        XCTAssertEqual(profile.speeds.count, 7)
        XCTAssertEqual(profile.speeds[0], 1)
        XCTAssertEqual(profile.speeds[1], 1)
        XCTAssertEqual(profile.speeds[2], 300)
        XCTAssertEqual(profile.speeds[3], defaultSpeeds[3])
    }

    func testWheelActionModeEncodingAndDecoding() throws {
        let profile = ShuttleProfile(
            name: "Browser Video",
            apps: ["com.google.Chrome"],
            speeds: defaultSpeeds,
            buttons: [:],
            jogMode: .upDown,
            jogInvert: true,
            shuttleMode: .leftRight,
            shuttleInvert: false
        )
        let data = try JSONEncoder().encode(ShuttleConfig(profiles: [profile]))
        let decoded = try JSONDecoder().decode(ShuttleConfig.self, from: data)
        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].jogMode, .upDown)
        XCTAssertTrue(decoded.profiles[0].jogInvert)
        XCTAssertEqual(decoded.profiles[0].shuttleMode, .leftRight)
        XCTAssertFalse(decoded.profiles[0].shuttleInvert)
    }

    func testWheelActionModeKeyMappingAndInvert() {
        // Scroll returns nil (handled by performScroll)
        XCTAssertNil(WheelActionMode.scroll.keyName(for: 1, inverted: false))
        XCTAssertNil(WheelActionMode.scroll.keyName(for: -1, inverted: true))

        // Up / Down: normal CW = down, CCW = up; inverted CW = up (volume up), CCW = down (volume down)
        XCTAssertEqual(WheelActionMode.upDown.keyName(for: 1, inverted: false), "down")
        XCTAssertEqual(WheelActionMode.upDown.keyName(for: -1, inverted: false), "up")
        XCTAssertEqual(WheelActionMode.upDown.keyName(for: 1, inverted: true), "up")
        XCTAssertEqual(WheelActionMode.upDown.keyName(for: -1, inverted: true), "down")

        // Left / Right
        XCTAssertEqual(WheelActionMode.leftRight.keyName(for: 1, inverted: false), "right")
        XCTAssertEqual(WheelActionMode.leftRight.keyName(for: -1, inverted: false), "left")
        XCTAssertEqual(WheelActionMode.leftRight.keyName(for: 1, inverted: true), "left")
        XCTAssertEqual(WheelActionMode.leftRight.keyName(for: -1, inverted: true), "right")

        // Page Up / Page Down
        XCTAssertEqual(WheelActionMode.pageUpDown.keyName(for: 1, inverted: false), "pagedown")
        XCTAssertEqual(WheelActionMode.pageUpDown.keyName(for: -1, inverted: false), "pageup")
        XCTAssertEqual(WheelActionMode.pageUpDown.keyName(for: 1, inverted: true), "pageup")
        XCTAssertEqual(WheelActionMode.pageUpDown.keyName(for: -1, inverted: true), "pagedown")
    }

    func testProfileMatchingAndHoverOnlyFilter() {
        let rdp = ShuttleProfile(
            name: "RDP",
            apps: ["com.microsoft.rdc.macos"],
            speeds: defaultSpeeds,
            buttons: ["1": "q"],
            hoverPriority: true
        )
        let browser = ShuttleProfile(
            name: "Browser",
            apps: ["com.google.Chrome"],
            speeds: defaultSpeeds,
            buttons: ["1": "command+t"],
            hoverPriority: false
        )
        let global = ShuttleProfile(
            name: "Global",
            apps: ["*"],
            speeds: defaultSpeeds,
            buttons: [:]
        )
        let profiles = [rdp, browser, global]

        XCTAssertEqual(
            AppController.matchProfile(appName: "Windows App", bundleId: "com.microsoft.rdc.macos", in: profiles, hoverOnly: true)?.name,
            "RDP"
        )
        XCTAssertNil(
            AppController.matchProfile(appName: "Google Chrome", bundleId: "com.google.Chrome", in: profiles, hoverOnly: true)
        )
        XCTAssertEqual(
            AppController.matchProfile(appName: "Unknown App", bundleId: "com.example.unknown", in: profiles, hoverOnly: false)?.name,
            "Global"
        )
    }
}

final class SettingsStoreTests: XCTestCase {

    func testUuidScopedBindingDoesNotOverwriteAnotherProfileAfterSelectionSwitch() {
        let profileA = ShuttleProfile(name: "A", apps: ["AppA"], speeds: defaultSpeeds, buttons: [:])
        let profileB = ShuttleProfile(name: "B", apps: ["AppB"], speeds: defaultSpeeds, buttons: [:])
        let store = SettingsStore(config: ShuttleConfig(profiles: [profileA, profileB]), selectedProfileId: profileA.id) { _ in }

        let bindingA = store.binding(for: profileA.id, fallback: profileA)

        // Simulate switching selection to B while a stale closure still holds A's binding
        store.selectedProfileId = profileB.id
        bindingA.wrappedValue.name = "A"

        XCTAssertEqual(store.profile(for: profileA.id)?.name, "A")
        XCTAssertEqual(store.profile(for: profileB.id)?.name, "B")
    }

    func testDeleteLastProfileInListDoesNotCrashAndKeepsStaleBindingSafe() {
        let profileA = ShuttleProfile(name: "A", apps: ["AppA"], speeds: defaultSpeeds, buttons: [:])
        let profileB = ShuttleProfile(name: "B", apps: ["AppB"], speeds: defaultSpeeds, buttons: [:])
        var savedConfigs: [ShuttleConfig] = []
        let store = SettingsStore(config: ShuttleConfig(profiles: [profileA, profileB]), selectedProfileId: profileB.id) { cfg in
            savedConfigs.append(cfg)
        }

        // Capture binding to the last profile before deletion
        let bindingB = store.binding(for: profileB.id, fallback: profileB)

        store.deleteSelectedProfile()

        XCTAssertEqual(store.config.profiles.count, 1)
        XCTAssertEqual(store.config.profiles[0].id, profileA.id)
        XCTAssertEqual(store.selectedProfileId, profileA.id)
        XCTAssertEqual(savedConfigs.count, 1)

        // Accessing or writing through the stale binding for the deleted last profile must not crash or mutate A
        XCTAssertEqual(bindingB.wrappedValue.name, "B")
        bindingB.wrappedValue.name = "StaleWrite"
        XCTAssertEqual(store.profile(for: profileA.id)?.name, "A")
    }

    func testDeleteOnlyRemainingProfileClearsSelectionWithoutCrashing() {
        let onlyProfile = ShuttleProfile(name: "Only", apps: ["*"], speeds: defaultSpeeds, buttons: [:])
        var saveCount = 0
        let store = SettingsStore(config: ShuttleConfig(profiles: [onlyProfile]), selectedProfileId: onlyProfile.id) { _ in
            saveCount += 1
        }

        let staleBinding = store.binding(for: onlyProfile.id, fallback: onlyProfile)

        store.deleteSelectedProfile()

        XCTAssertTrue(store.config.profiles.isEmpty)
        XCTAssertNil(store.selectedProfileId)
        XCTAssertEqual(saveCount, 1)

        // Reading or writing stale binding after array becomes empty must not crash
        XCTAssertEqual(staleBinding.wrappedValue.name, "Only")
        staleBinding.wrappedValue.name = "Ignored"
        XCTAssertTrue(store.config.profiles.isEmpty)
    }

    func testSettingsViewSwitchingAndDeletingLastProfileInHostingView() {
        _ = NSApplication.shared
        let profileA = ShuttleProfile(name: "A", apps: ["AppA"], speeds: defaultSpeeds, buttons: [:])
        let profileB = ShuttleProfile(name: "B", apps: ["AppB"], speeds: defaultSpeeds, buttons: [:])
        let store = SettingsStore(config: ShuttleConfig(profiles: [profileA, profileB]), selectedProfileId: profileA.id) { _ in }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SettingsView(store: store))
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        func findEditableTextField(in view: NSView, matching value: String) -> NSTextField? {
            if let tf = view as? NSTextField, tf.isEditable, tf.stringValue == value {
                return tf
            }
            for subview in view.subviews {
                if let found = findEditableTextField(in: subview, matching: value) {
                    return found
                }
            }
            return nil
        }

        // Focus Profile A's Name TextField, then switch selection to B
        let nameFieldA = findEditableTextField(in: hostingView, matching: "A")
        XCTAssertNotNil(nameFieldA, "Expected editable TextField for Profile A")
        if let nameFieldA {
            window.makeFirstResponder(nameFieldA)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        store.selectedProfileId = profileB.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(store.profile(for: profileA.id)?.name, "A")
        XCTAssertEqual(store.profile(for: profileB.id)?.name, "B")

        // Focus Profile B's Name TextField, then switch back to A and verify neither is overwritten
        let nameFieldB = findEditableTextField(in: hostingView, matching: "B")
        XCTAssertNotNil(nameFieldB, "Expected editable TextField for Profile B")
        if let nameFieldB {
            window.makeFirstResponder(nameFieldB)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        store.selectedProfileId = profileA.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(store.profile(for: profileA.id)?.name, "A")
        XCTAssertEqual(store.profile(for: profileB.id)?.name, "B")

        // Select last profile (B), focus its field, and delete it
        store.selectedProfileId = profileB.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        if let nameFieldBForDelete = findEditableTextField(in: hostingView, matching: "B") {
            window.makeFirstResponder(nameFieldBForDelete)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        store.deleteSelectedProfile()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(store.config.profiles.count, 1)
        XCTAssertEqual(store.selectedProfileId, profileA.id)
        XCTAssertEqual(store.profile(for: profileA.id)?.name, "A")

        // Delete the only remaining profile (A)
        store.deleteSelectedProfile()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(store.config.profiles.isEmpty)
        XCTAssertNil(store.selectedProfileId)
        window.close()
    }
}

final class ProfileConflictDetectorTests: XCTestCase {

    func testBasicOrderOverlapDetectionCaseInsensitive() {
        let top = ShuttleProfile(name: "Top", apps: ["com.google.Chrome"], speeds: defaultSpeeds, buttons: [:])
        let bottom = ShuttleProfile(name: "Bottom", apps: ["COM.GOOGLE.CHROME"], speeds: defaultSpeeds, buttons: [:])
        let profiles = [top, bottom]

        let topOverlaps = ProfileConflictDetector.overlaps(for: "com.google.Chrome", in: top.id, profiles: profiles)
        XCTAssertEqual(topOverlaps.count, 1)
        XCTAssertEqual(topOverlaps[0].kind, .shadowsLower)
        XCTAssertFalse(topOverlaps[0].isWarning)
        XCTAssertFalse(ProfileConflictDetector.profileHasWarnings(profileId: top.id, profiles: profiles))

        let bottomOverlaps = ProfileConflictDetector.overlaps(for: "COM.GOOGLE.CHROME", in: bottom.id, profiles: profiles)
        XCTAssertEqual(bottomOverlaps.count, 1)
        XCTAssertEqual(bottomOverlaps[0].kind, .shadowedByHigher)
        XCTAssertTrue(bottomOverlaps[0].isWarning)
        XCTAssertTrue(ProfileConflictDetector.profileHasWarnings(profileId: bottom.id, profiles: profiles))
    }

    func testHoverPriorityConflictAcrossProfiles() {
        let topNoHover = ShuttleProfile(
            name: "TopNormal",
            apps: ["com.microsoft.rdc.macos"],
            speeds: defaultSpeeds,
            buttons: [:],
            hoverPriority: false
        )
        let bottomHover = ShuttleProfile(
            name: "BottomHover",
            apps: ["com.microsoft.rdc.macos"],
            speeds: defaultSpeeds,
            buttons: [:],
            hoverPriority: true
        )
        let profiles = [topNoHover, bottomHover]

        let topOverlaps = ProfileConflictDetector.overlaps(for: "com.microsoft.rdc.macos", in: topNoHover.id, profiles: profiles)
        XCTAssertEqual(topOverlaps.first?.kind, .overriddenOnHoverByLower)
        XCTAssertTrue(ProfileConflictDetector.profileHasWarnings(profileId: topNoHover.id, profiles: profiles))

        let bottomOverlaps = ProfileConflictDetector.overlaps(for: "com.microsoft.rdc.macos", in: bottomHover.id, profiles: profiles)
        XCTAssertEqual(bottomOverlaps.first?.kind, .shadowedExceptHover)
        XCTAssertTrue(ProfileConflictDetector.profileHasWarnings(profileId: bottomHover.id, profiles: profiles))
    }

    func testAliasOverlapBetweenAppNameAndBundleId() {
        let aliases = [AppAlias(name: "Google Chrome", bundleId: "com.google.Chrome")]
        let top = ShuttleProfile(name: "ByName", apps: ["Google Chrome"], speeds: defaultSpeeds, buttons: [:])
        let bottom = ShuttleProfile(name: "ByBundle", apps: ["com.google.Chrome"], speeds: defaultSpeeds, buttons: [:])
        let profiles = [top, bottom]

        let overlaps = ProfileConflictDetector.overlaps(for: "com.google.Chrome", in: bottom.id, profiles: profiles, aliases: aliases)
        XCTAssertEqual(overlaps.count, 1)
        XCTAssertEqual(overlaps[0].kind, .shadowedByHigher)
        XCTAssertTrue(overlaps[0].isAliasMatch)
        XCTAssertEqual(overlaps[0].matchedEntry, "Google Chrome")
    }

    func testWildcardDuplicateAndMixedWildcardWarnings() {
        let global1 = ShuttleProfile(name: "Global 1", apps: ["*"], speeds: defaultSpeeds, buttons: [:])
        let global2 = ShuttleProfile(name: "Global 2", apps: ["*"], speeds: defaultSpeeds, buttons: [:])
        let mixed = ShuttleProfile(name: "Mixed", apps: ["*", "Safari"], speeds: defaultSpeeds, buttons: [:])
        let profiles = [global1, global2, mixed]

        let global2Overlaps = ProfileConflictDetector.overlaps(for: "*", in: global2.id, profiles: profiles)
        XCTAssertTrue(global2Overlaps.contains(where: { $0.otherProfileId == global1.id && $0.kind == .shadowedByHigher }))
        XCTAssertTrue(ProfileConflictDetector.hasMixedWildcard(in: mixed))
        XCTAssertTrue(ProfileConflictDetector.profileHasWarnings(profileId: mixed.id, profiles: profiles))
    }

    func testMoveAppRemovesFromConflictingProfilesAndAddsToTarget() {
        let aliases = [AppAlias(name: "Google Chrome", bundleId: "com.google.Chrome")]
        let profileA = ShuttleProfile(name: "A", apps: ["Google Chrome", "Safari"], speeds: defaultSpeeds, buttons: [:])
        let profileB = ShuttleProfile(name: "B", apps: ["Firefox"], speeds: defaultSpeeds, buttons: [:])
        var saveCount = 0
        let store = SettingsStore(config: ShuttleConfig(profiles: [profileA, profileB]), selectedProfileId: profileB.id) { _ in
            saveCount += 1
        }

        store.moveApp("com.google.Chrome", to: profileB.id, aliases: aliases)

        XCTAssertEqual(store.profile(for: profileA.id)?.apps, ["Safari"])
        XCTAssertEqual(store.profile(for: profileB.id)?.apps, ["Firefox", "com.google.Chrome"])
        XCTAssertEqual(saveCount, 1)
    }
}
