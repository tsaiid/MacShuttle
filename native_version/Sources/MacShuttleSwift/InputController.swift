import Foundation
import CoreGraphics
import AppKit

class InputController {
    
    static let shared = InputController()
    
    private init() {}
    
    func performScroll(direction: Int, multiplier: Int) {
        // direction: 1 or -1
        // multiplier: amount
        // Python: dy = -1 if direction > 0 else 1
        // mouse.scroll(0, dy * multiplier)
        // In CGEvent, scroll wheel 1 is Y axis. + is up (usually), - is down.
        // Python pynput: scroll(0, 1) -> Up.
        // Shuttle: Right turn (direction > 0) -> usually Scroll Down in content?
        // Python code: dy = -1 if direction > 0 else 1.
        // So direction > 0 (Right) -> dy = -1 (Scroll Down).
        
        // CGEventScrollWheel1
        // unit: line or pixel. Pynput uses "steps". CGEvent uses line.
        let scrollY = Int32(direction > 0 ? -1 * multiplier : 1 * multiplier)
        
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: scrollY, wheel2: 0, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    func performKey(keyDef: String) {
        let lower = keyDef.lowercased()
        var modifiers: CGEventFlags = []
        var baseKey = lower
        
        if lower.contains("+") {
            let parts = lower.split(separator: "+").map { String($0) }
            baseKey = parts.last ?? ""
            if parts.contains("command") || parts.contains("cmd") { modifiers.insert(.maskCommand) }
            if parts.contains("shift") { modifiers.insert(.maskShift) }
            if parts.contains("control") || parts.contains("ctrl") { modifiers.insert(.maskControl) }
            if parts.contains("option") || parts.contains("alt") { modifiers.insert(.maskAlternate) }
        }
        
        guard let keyCode = macKeyCodes[baseKey] else {
            print("Unknown key: \(baseKey)")
            return
        }
        
        // Create Key Down
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        keyDown.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        
        // Create Key Up
        // Slight delay is usually good for compatibility, but native events are fast.
        // Python used 0.15s sleep.
        usleep(150000) // 150ms
        
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        keyUp.flags = modifiers
        keyUp.post(tap: .cghidEventTap)
    }
}
