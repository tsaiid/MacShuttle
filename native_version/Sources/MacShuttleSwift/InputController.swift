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
        // Native Implementation using CGEventSource(.hidSystemState)
        
        let lower = keyDef.lowercased()
        var modifiers: [String] = []
        var baseKey = lower
        
        // 1. Analyze Modifiers
        if lower.contains("+") {
            let parts = lower.split(separator: "+").map { String($0) }
            baseKey = parts.last ?? ""
            
            if parts.count > 1 {
                for part in parts.dropLast() {
                    if part.contains("cmd") || part.contains("command") { modifiers.append("command") }
                    if part.contains("shift") { modifiers.append("shift") }
                    if part.contains("ctrl") || part.contains("control") { modifiers.append("control") }
                    if part.contains("opt") || part.contains("alt") { modifiers.append("option") }
                }
            }
        }
        
        // 2. Handle Implicit Shift
        if modifiers.isEmpty && keyDef.count == 1 && keyDef.uppercased() == keyDef && keyDef.lowercased() != keyDef {
            modifiers.append("shift")
            baseKey = keyDef.lowercased()
        }
        
        baseKey = baseKey.lowercased()
        
        guard let keyCode = macKeyCodes[baseKey] else {
            print("Unknown key: \(baseKey)")
            return
        }
        
        // 3. Execution with .hidSystemState Source
        
        let modKeyCodes: [String: CGKeyCode] = [
            "shift": 56,
            "control": 59,
            "option": 58,
            "command": 55
        ]
        
        // Step A: Press Modifiers
        for mod in modifiers {
            if let modCode = modKeyCodes[mod] {
                postKeyEvent(keyCode: modCode, keyDown: true)
            }
        }
        
        // Critical Delay for RDP to recognize modifier state change
        if !modifiers.isEmpty {
            usleep(50000) // 50ms
        }
        
        // Step B: Press & Release Main Key
        postKeyEvent(keyCode: keyCode, keyDown: true)
        usleep(20000) // 20ms Hold
        postKeyEvent(keyCode: keyCode, keyDown: false)
        
        // Critical Delay before releasing modifiers
        if !modifiers.isEmpty {
            usleep(50000) // 50ms
        }
        
        // Step C: Release Modifiers
        for mod in modifiers.reversed() {
            if let modCode = modKeyCodes[mod] {
                postKeyEvent(keyCode: modCode, keyDown: false)
            }
        }
    }
    
    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool) {
        // We use the shared eventSource (.hidSystemState) here
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.post(tap: .cghidEventTap)
    }
}
