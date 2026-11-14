import XCTest
import AppKit
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
        XCTAssertEqual(profile.speeds.count, 7)
        XCTAssertEqual(profile.speeds[0], 1)
        XCTAssertEqual(profile.speeds[1], 1)
        XCTAssertEqual(profile.speeds[2], 300)
        XCTAssertEqual(profile.speeds[3], defaultSpeeds[3])
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
