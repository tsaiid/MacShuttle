import Foundation
import CoreGraphics
import AppKit

struct ShuttleProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var apps: [String]
    var speeds: [Int] // 7 levels, in ms
    var buttons: [String: String] // "1": "cmd+c"

    enum CodingKeys: String, CodingKey {
        case id, name, apps, speeds, buttons
    }

    init(name: String, apps: [String], speeds: [Int], buttons: [String: String]) {
        self.id = UUID()
        self.name = name
        self.apps = apps
        self.speeds = speeds
        self.buttons = buttons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        apps = try container.decode([String].self, forKey: .apps)
        speeds = try container.decode([Int].self, forKey: .speeds)
        buttons = try container.decode([String: String].self, forKey: .buttons)
        // Use existing ID if present, otherwise generate new one
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(apps, forKey: .apps)
        try container.encode(speeds, forKey: .speeds)
        try container.encode(buttons, forKey: .buttons)
    }
}

struct ShuttleConfig: Codable, Hashable {
    var profiles: [ShuttleProfile]
}

let defaultSpeeds = [800, 600, 333, 200, 100, 50, 20]

let defaultProfileWindows = ShuttleProfile(
    name: "Windows Remote",
    apps: ["Windows App", "Microsoft Remote Desktop", "WindowsApp", "rdp", "com.microsoft.rdc.macos", "com.microsoft.rdc.osx"],
    speeds: defaultSpeeds,
    buttons: [
        "1": "q", "2": "7", "3": "5", "4": "6", "5": "d",
        "6": "8", "7": "1", "8": "9", "9": "4", "10": "x",
        "11": "f", "12": "", "13": "w", "14": "o", "15": "down"
    ]
)

let defaultProfileBrowser = ShuttleProfile(
    name: "Chrome / Browser",
    apps: ["Google Chrome", "Safari", "Microsoft Edge", "Arc", "com.google.Chrome", "com.apple.Safari"],
    speeds: [500, 300, 150, 80, 40, 20, 10],
    buttons: [
        "1": "command+t",
        "2": "command+w",
        "3": "command+r",
        "13": "space"
    ]
)

let defaultProfileGlobal = ShuttleProfile(
    name: "Default (Global)",
    apps: ["*"],
    speeds: defaultSpeeds,
    buttons: [:]
)

let defaultConfig = ShuttleConfig(profiles: [
    defaultProfileWindows,
    defaultProfileBrowser,
    defaultProfileGlobal
])

// Key Code Map
let macKeyCodes: [String: CGKeyCode] = [
    // Letters
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
    "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,

    // Numbers (Top Row)
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,

    // Symbols & Aliases
    "=": 24, "equal": 24, "equals": 24,
    "+": 24, "plus": 24,
    "-": 27, "minus": 27,
    "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "\\": 42, "`": 50,

    // Functional & Control Keys with Aliases
    "return": 36, "enter": 36,
    "tab": 48, "space": 49,
    "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53,
    "forwarddelete": 117, "del": 117,

    // Navigation & Arrows
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,

    // Function Keys
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,

    // Keypad (Numpad) Keys & Aliases
    "keypad0": 82, "keypad1": 83, "keypad2": 84, "keypad3": 85, "keypad4": 86,
    "keypad5": 87, "keypad6": 88, "keypad7": 89, "keypad8": 91, "keypad9": 92,
    "numpad0": 82, "numpad1": 83, "numpad2": 84, "numpad3": 85, "numpad4": 86,
    "numpad5": 87, "numpad6": 88, "numpad7": 89, "numpad8": 91, "numpad9": 92,
    "keypaddecimal": 65, "keypadmultiply": 67, "keypaddivide": 75,
    "keypadplus": 69, "keypadminus": 78, "keypadenter": 76, "keypadequals": 81,

    // Modifiers
    "command": 55, "cmd": 55, "shift": 56, "capslock": 57, "option": 58, "opt": 58,
    "control": 59, "ctrl": 59, "right_command": 54, "right_shift": 60, "right_option": 61,
    "right_control": 62, "fn": 63
]

struct ShortcutFormatter {
    static let keyCodeToName: [CGKeyCode: String] = [
        // Letters (ANSI)
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k",
        45: "n", 46: "m",

        // Numbers
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",

        // Symbols
        24: "equal", 27: "minus", 33: "[", 30: "]", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",

        // Functional / Whitespace
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape", 117: "forwarddelete",

        // Arrows
        123: "left", 124: "right", 125: "down", 126: "up",

        // Navigation
        115: "home", 119: "end", 116: "pageup", 121: "pagedown",

        // Function keys
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",

        // Keypad
        82: "keypad0", 83: "keypad1", 84: "keypad2", 85: "keypad3", 86: "keypad4",
        87: "keypad5", 88: "keypad6", 89: "keypad7", 91: "keypad8", 92: "keypad9",
        65: "keypaddecimal", 67: "keypadmultiply", 69: "keypadplus", 75: "keypaddivide",
        76: "enter", 78: "keypadminus", 81: "keypadequals"
    ]

    static func canonicalName(for keyCode: CGKeyCode) -> String {
        return keyCodeToName[keyCode] ?? "key_\(keyCode)"
    }

    static func canonicalString(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { parts.append("control") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("command") }

        parts.append(canonicalName(for: keyCode))
        return parts.joined(separator: "+")
    }

    static func modifierDisplayString(modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    static func parseKeyDefinition(_ keyDef: String) -> (baseKey: String, modifiers: [String]) {
        let trimmedKeyDef = keyDef.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmedKeyDef.lowercased()
        var modifiers: [String] = []
        var baseKey = lower

        if lower == "+" {
            baseKey = "plus"
        } else if lower.hasSuffix("++") {
            let prefix = String(lower.dropLast(2))
            baseKey = "plus"
            for part in prefix.split(separator: "+") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if p.contains("cmd") || p.contains("command") { modifiers.append("command") }
                if p.contains("shift") { modifiers.append("shift") }
                if p.contains("ctrl") || p.contains("control") { modifiers.append("control") }
                if p.contains("opt") || p.contains("alt") { modifiers.append("option") }
            }
        } else if lower.contains("+") {
            let parts = lower.split(separator: "+").map { String($0) }
            baseKey = parts.last ?? ""

            if parts.count > 1 {
                for part in parts.dropLast() {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if p.contains("cmd") || p.contains("command") { modifiers.append("command") }
                    if p.contains("shift") { modifiers.append("shift") }
                    if p.contains("ctrl") || p.contains("control") { modifiers.append("control") }
                    if p.contains("opt") || p.contains("alt") { modifiers.append("option") }
                }
            }
        }

        // Implicit Shift for single uppercase characters (e.g. "Z")
        if modifiers.isEmpty && trimmedKeyDef.count == 1 &&
            trimmedKeyDef.uppercased() == trimmedKeyDef &&
            trimmedKeyDef.lowercased() != trimmedKeyDef {
            modifiers.append("shift")
            baseKey = trimmedKeyDef.lowercased()
        }

        return (baseKey.lowercased().trimmingCharacters(in: .whitespaces), modifiers)
    }

    static func displayString(for keyDef: String) -> String {
        let trimmed = keyDef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let (baseKey, modifiers) = parseKeyDefinition(trimmed)
        var result = ""
        if modifiers.contains("control") { result += "⌃" }
        if modifiers.contains("option") { result += "⌥" }
        if modifiers.contains("shift") { result += "⇧" }
        if modifiers.contains("command") { result += "⌘" }

        result += displayBaseKey(baseKey)
        return result
    }

    private static func displayBaseKey(_ baseKey: String) -> String {
        switch baseKey.lowercased() {
        case "space": return "Space"
        case "escape", "esc": return "Esc"
        case "return", "enter": return "Return"
        case "delete", "backspace": return "Delete"
        case "forwarddelete", "del": return "Del"
        case "tab": return "Tab"
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        case "pageup": return "PageUp"
        case "pagedown": return "PageDown"
        case "home": return "Home"
        case "end": return "End"
        case "plus", "+": return "+"
        case "minus", "-": return "-"
        case "equal", "=": return "="
        case "keypadplus": return "Num +"
        case "keypadminus": return "Num -"
        case "keypadmultiply": return "Num *"
        case "keypaddivide": return "Num /"
        case "keypaddecimal": return "Num ."
        case "keypadequals": return "Num ="
        case let k where k.hasPrefix("keypad") || k.hasPrefix("numpad"):
            let num = k.replacingOccurrences(of: "keypad", with: "").replacingOccurrences(of: "numpad", with: "")
            return "Num \(num)"
        case let k where k.hasPrefix("f") && k.count <= 3:
            return k.uppercased()
        case let k where k.count == 1:
            return k.uppercased()
        default:
            return baseKey.capitalized
        }
    }
}
