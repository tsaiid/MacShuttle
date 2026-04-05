import Foundation
import CoreGraphics
import AppKit

class InputController {
    
    static let shared = InputController()
    
    // Create a persistent source tied to the HID System State.
    // This tells the OS that these events should update the global hardware input state.
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    
    private init() {}
    
    func performScroll(direction: Int, multiplier: Int) {
        let scrollY = Int32(direction > 0 ? -1 * multiplier : 1 * multiplier)
        if let event = CGEvent(scrollWheelEvent2Source: eventSource, units: .line, wheelCount: 1, wheel1: scrollY, wheel2: 0, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    func performKey(keyDef: String) {
        let lower = keyDef.lowercased()
        var modifiers: [String] = []
        var baseKey = lower
        
        // 1. Analyze Modifiers
        if lower.contains("+") {
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
        
        // 2. Handle Implicit Shift
        if modifiers.isEmpty && keyDef.count == 1 && keyDef.uppercased() == keyDef && keyDef.lowercased() != keyDef {
            modifiers.append("shift")
            baseKey = keyDef.lowercased()
        }
        
        baseKey = baseKey.lowercased().trimmingCharacters(in: .whitespaces)
        
        guard let keyCode = macKeyCodes[baseKey] else {
            print("Unknown key: \(baseKey)")
            return
        }
        
        // 分流實作：
        // 1. 若無修飾鍵 (modifiers.isEmpty)，直接使用 CGEvent 以獲得最高反應速度（適合 Jog/Shuttle 快速轉動）。
        // 2. 若有修飾鍵 (例如 Z 或 Cmd+C)，使用 NSAppleScript 以確保在 RDP/Windows App 下的穩定性。
        
        if modifiers.isEmpty {
            postKeyEvent(keyCode: keyCode, keyDown: true)
            postKeyEvent(keyCode: keyCode, keyDown: false)
        } else {
            // AppleScript Execution (mimics osascript for RDP compatibility)
            var scriptSource = "tell application \"System Events\" to key code \(keyCode)"
            
            let appleScriptModifiers = modifiers.map { mod -> String in
                switch mod {
                case "command": return "command down"
                case "shift": return "shift down"
                case "control": return "control down"
                case "option": return "option down"
                default: return ""
                }
            }.filter { !$0.isEmpty }.joined(separator: ", ")
            
            if !appleScriptModifiers.isEmpty {
                scriptSource += " using {\(appleScriptModifiers)}"
            }
            
            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let err = error {
                    print("AppleScript Error: \(err)")
                }
            }
        }
    }
    
    // Kept for backward compatibility or direct calls if needed
    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.post(tap: .cghidEventTap)
    }
}
