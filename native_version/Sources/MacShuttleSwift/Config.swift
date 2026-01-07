import Foundation

struct ShuttleProfile: Codable {
    var name: String
    var apps: [String]
    var speeds: [Int] // 7 levels, in ms
    var buttons: [String: String] // "1": "cmd+c"
}

struct ShuttleConfig: Codable {
    var profiles: [ShuttleProfile]
}

let defaultSpeeds = [800, 600, 333, 200, 100, 50, 20]

let defaultProfileWindows = ShuttleProfile(
    name: "Windows Remote",
    apps: ["Windows App", "Microsoft Remote Desktop", "WindowsApp", "rdp"],
    speeds: defaultSpeeds,
    buttons: [
        "1": "q", "2": "7", "3": "5", "4": "6", "5": "d",
        "6": "8", "7": "1", "8": "9", "9": "4", "10": "x",
        "11": "f", "12": "", "13": "w", "14": "o", "15": "down"
    ]
)

let defaultProfileBrowser = ShuttleProfile(
    name: "Chrome / Browser",
    apps: ["Google Chrome", "Safari", "Microsoft Edge", "Arc"],
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
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 36, "escape": 53,
    "down": 125, "up": 126, "left": 123, "right": 124, "f1": 122, "f2": 120, "f3": 99,
    "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
    "f11": 103, "f12": 111, "command": 55, "shift": 56, "capslock": 57, "option": 58,
    "control": 59, "right_command": 54, "right_shift": 60, "right_option": 61,
    "right_control": 62, "fn": 63
]

import CoreGraphics
