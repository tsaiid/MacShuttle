import Foundation

/// Shuttle 外圈撥輪滾動狀態機 (ShuttleScrollEngine)
/// 職責：
/// 1. 速度級距換算 (Speed level to period interval)
/// 2. 啟動緩衝區 (Startup buffer delay) 防抖
/// 3. 動態變速平滑過渡 (Transition logic between speeds)
/// 4. RunLoop .common 模式下的定時滾動與生命週期管理
class ShuttleScrollEngine {
    
    // MARK: - Properties
    
    /// 當前 Shuttle 撥輪數值（-7 至 7，0 表示停止）
    private(set) var currentSpeed: Int = 0
    
    /// 各速度級距之定時週期（單位：毫秒，預設 7 個級距）
    var speeds: [Int] = defaultSpeeds
    
    /// 啟動緩衝等待時間（秒，預設 0.08 秒）
    var startupDelay: TimeInterval = 0.08
    
    /// 滾動事件觸發之回呼閉包，預設直接呼叫 InputController.shared.performScroll
    var onScroll: ((_ direction: Int) -> Void)? = { direction in
        InputController.shared.performScroll(direction: direction, multiplier: 2)
    }
    
    // MARK: - State Machine Internals
    
    private var scrollTimer: Timer?
    private var isTransitioning: Bool = false
    private var targetPeriod: Double = 0
    private var isStartupPending: Bool = false
    private var startupWorkItem: DispatchWorkItem?
    
    // MARK: - Lifecycle
    
    init(speeds: [Int] = defaultSpeeds) {
        self.speeds = speeds
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public API
    
    /// 處理來自 HID 的 Shuttle 撥輪數值更新
    /// - Parameters:
    ///   - value: 撥輪數值 (-7 ~ 7, 0 為回正停止)
    ///   - speeds: 可選的自訂速度級距清單（若未提供則使用實例之 speeds）
    func updateShuttle(value: Int, speeds: [Int]? = nil) {
        if let speeds = speeds {
            self.speeds = speeds
        }
        
        if value == currentSpeed {
            return
        }
        
        // 1. 停止狀態 (Stop)
        if value == 0 {
            stop()
            return
        }
        
        // 2. 處於啟動緩衝等待期中，僅更新目標速度
        if isStartupPending {
            currentSpeed = value
            return
        }
        
        // 3. 從靜止狀態 (0) 啟動，進入啟動緩衝區 (Startup Buffer)
        if currentSpeed == 0 {
            isStartupPending = true
            currentSpeed = value
            
            startupWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeStartup()
            }
            startupWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + startupDelay, execute: workItem)
            return
        }
        
        // 4. 動態變速過渡邏輯 (Transition logic)
        isTransitioning = false
        let newPeriod = getPeriod(speed: value)
        let oldPeriod = getPeriod(speed: currentSpeed)
        var waitDelay: Double = 0
        
        if abs(value) > abs(currentSpeed) {
            // 加速：半差值延遲
            waitDelay = abs(oldPeriod - newPeriod) / 2.0
        } else if abs(value) < abs(currentSpeed) {
            // 減速：半合值延遲
            waitDelay = (oldPeriod + newPeriod) / 2.0
        }
        
        currentSpeed = value
        
        // 重新排程定時器
        scrollTimer?.invalidate()
        
        if waitDelay < 0.04 {
            // 延遲極小，視為即時切換
            performScrollAction()
            startScrollTimer(interval: newPeriod)
        } else {
            isTransitioning = true
            targetPeriod = newPeriod
            let timer = Timer(timeInterval: waitDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.performScrollAction()
                self.startScrollTimer(interval: self.targetPeriod)
                self.isTransitioning = false
            }
            RunLoop.main.add(timer, forMode: .common)
            scrollTimer = timer
        }
    }
    
    /// 停止所有定時器並重置狀態機至靜止狀態
    func stop() {
        currentSpeed = 0
        scrollTimer?.invalidate()
        scrollTimer = nil
        isTransitioning = false
        isStartupPending = false
        startupWorkItem?.cancel()
        startupWorkItem = nil
    }
    
    /// 重置狀態機（等同於 stop）
    func reset() {
        stop()
    }
    
    /// 計算給定速度級距對應的滾動週期時間（秒）
    func getPeriod(speed: Int) -> Double {
        let idx = min(max(abs(speed) - 1, 0), 6)
        if idx < speeds.count {
            return Double(speeds[idx]) / 1000.0
        }
        return 0.1
    }
    
    // MARK: - Private Helpers
    
    private func executeStartup() {
        isStartupPending = false
        startupWorkItem = nil
        
        if currentSpeed == 0 { return }
        
        let period = getPeriod(speed: currentSpeed)
        performScrollAction()
        startScrollTimer(interval: period)
        isTransitioning = false
    }
    
    private func startScrollTimer(interval: Double) {
        scrollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.performScrollAction()
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }
    
    private func performScrollAction() {
        if currentSpeed == 0 { return }
        let direction = currentSpeed > 0 ? 1 : -1
        onScroll?(direction)
    }
}
