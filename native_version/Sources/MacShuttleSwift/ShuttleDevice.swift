import Foundation
import IOKit.hid

protocol ShuttleDeviceDelegate: AnyObject {
    func shuttleDevice(_ device: ShuttleDevice, didUpdateShuttle value: Int)
    func shuttleDevice(_ device: ShuttleDevice, didUpdateJog value: Int)
    func shuttleDevice(_ device: ShuttleDevice, didUpdateButtons mask: UInt32)
    func shuttleDeviceDidConnect(_ device: ShuttleDevice)
    func shuttleDeviceDidDisconnect(_ device: ShuttleDevice)
}

class ShuttleDevice {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    weak var delegate: ShuttleDeviceDelegate?
    
    let vid: Int = 0x0b33
    let pid: Int = 0x0030
    
    // Indices based on Python code
    let SHUTTLE_INDEX = 0
    let JOG_INDEX = 1
    let BUTTON_LOW_INDEX = 3
    let BUTTON_HIGH_INDEX = 4
    
    init() {
        setupHID()
    }
    
    private func setupHID() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let deviceCriteria: [String: Any] = [
            kIOHIDVendorIDKey: vid,
            kIOHIDProductIDKey: pid
        ]
        
        IOHIDManagerSetDeviceMatching(manager!, deviceCriteria as CFDictionary)
        
        let matchCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let mySelf = Unmanaged<ShuttleDevice>.fromOpaque(context!).takeUnretainedValue()
            mySelf.deviceConnected(device)
        }
        
        let removeCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let mySelf = Unmanaged<ShuttleDevice>.fromOpaque(context!).takeUnretainedValue()
            mySelf.deviceDisconnected(device)
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager!, matchCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager!, removeCallback, context)
        
        IOHIDManagerScheduleWithRunLoop(manager!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let ret = IOHIDManagerOpen(manager!, IOOptionBits(kIOHIDOptionsTypeNone))
        if ret != kIOReturnSuccess {
            print("Failed to open HID Manager")
        }
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        print("Shuttle Connected")
        self.device = device
        
        let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportId, report, reportLength in
            let mySelf = Unmanaged<ShuttleDevice>.fromOpaque(context!).takeUnretainedValue()
            let data = UnsafeBufferPointer(start: report, count: reportLength)
            mySelf.handleReport(Array(data))
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Register for input reports
        // Note: Buffer size is typically small (e.g., 5-64 bytes)
        let bufferSize = 64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, reportCallback, context)
        
        delegate?.shuttleDeviceDidConnect(self)
    }
    
    private func deviceDisconnected(_ device: IOHIDDevice) {
        print("Shuttle Disconnected")
        self.device = nil
        delegate?.shuttleDeviceDidDisconnect(self)
    }
    
    private func handleReport(_ data: [UInt8]) {
        // Python logic:
        // shuttle = data[SHUTTLE_INDEX]
        // jog = data[JOG_INDEX]
        // buttons = (data[HIGH] << 8) | data[LOW]
        
        guard data.count > BUTTON_HIGH_INDEX else { return }
        
        let shuttleRaw = Int(data[SHUTTLE_INDEX])
        // Convert to signed 8-bit
        let shuttleVal = (shuttleRaw > 127) ? shuttleRaw - 256 : shuttleRaw
        
        let jogRaw = Int(data[JOG_INDEX])
        
        let bLow = Int(data[BUTTON_LOW_INDEX])
        let bHigh = Int(data[BUTTON_HIGH_INDEX])
        let buttonMask = UInt32((bHigh << 8) | bLow)
        
        delegate?.shuttleDevice(self, didUpdateShuttle: shuttleVal)
        delegate?.shuttleDevice(self, didUpdateJog: jogRaw)
        delegate?.shuttleDevice(self, didUpdateButtons: buttonMask)
    }
}
