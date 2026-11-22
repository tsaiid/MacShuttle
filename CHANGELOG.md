# Changelog

All notable changes to **MacShuttle** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-22

### Added
- **Jog 與 Shuttle 獨立輸出模式與方向反轉 (`WheelActionMode`)**：
  - 每個 Profile 可分別設定 **Jog Wheel (內圈)** 與 **Shuttle Wheel (外圈)** 的輸出模式，支援 `Scroll (Vertical)`、`Up / Down`、`Left / Right`、`Page Up / Page Down`，並向下相容舊版 `shuttle_config.json`。
  - 新增「反轉方向 (Invert)」開關與即時 `↺ / ↻` 方向提示，方便依情境反轉順／逆時針對應（例如以 Jog 順時針調大網頁影片音量）。
  - 輪盤事件發送皆不自動切換前景視窗，避免干擾原本操作焦點。
- **單元測試補強**：新增 `WheelActionMode` 編解碼、舊版 JSON 向下相容與各模式反轉映射測試（共 19 項 `XCTest` 測試）。

### Changed
- **偏好設定介面調整**：將第三個分頁 `Shuttle Speeds` 改名為 `Jog & Shuttle`，並將偏好設定視窗預設與最小高度由 `600` 調整為 `700`，完整顯示輪盤設定與 7 段速度清單。

## [1.1.0] - 2026-11-22

### Added
- **跨 Profile App 重疊防呆與衝突提示 (`ProfileConflictDetector`)**：
  - 保留多套 Profile 依側邊欄順序切換的彈性，並於側邊欄新增「優先順序由上而下，可拖曳調整」提示與衝突 ⚠️ 標記。
  - 在 `Target Apps` 清單中即時顯示行內提示：包含順序覆蓋（被上方覆蓋 / 優先於下方）、`Hover Priority` 跨 Profile 搶佔提示、執行中 App 的 Name ↔ Bundle ID 隱性重疊偵測，以及同 Profile 混用 `*` 與特定 App 的警示橫幅。
  - 透過輸入、「從執行中程式加入」或「瀏覽...」新增重複 App 時，彈出對話框提供「移動至此設定檔」、「兩邊都保留」或「取消」。
- **單元測試補強**：新增 `ProfileConflictDetectorTests`（5 項測試，共 17 項 `XCTest` 測試）。

## [1.0.1] - 2026-11-22

### Fixed
- **偏好設定切換 Profile 名稱誤覆寫**：改用 UUID 綁定與 View Identity 隔離（`.id(selectedId)`）並保留分頁狀態，修正滑鼠切換 Profile 時舊有輸入框焦點失焦導致下一個 Profile 名稱被前一個覆寫的問題。
- **刪除最後一個 Profile 閃退**：移除索引型陣列 Binding，改以安全 UUID 查找與先更新選取狀態再移除元素，修正刪除清單最後一筆或唯一一筆 Profile 時觸發 `Index out of range` 閃退的問題。
- **單元測試補強**：新增 `SettingsStoreTests` 驗證跨 Profile 切換隔離與刪除最後/唯一 Profile 的穩定性（共 12 項 `XCTest` 測試）。

## [1.0.0] - 2026-11-15

### Added
- **Native Swift macOS App**：基於 `IOKit.hid` 的低資源佔用 Menu Bar 應用程式，支援 Contour ShuttlePRO v2 / ShuttleXpress / ShuttlePRO v1。
- **混合式按鍵注入引擎**：無修飾鍵走 `CGEvent` 低延遲通道，複合鍵與大寫字元走背景串行佇列預編譯 `NSAppleScript` 通道，確保 RDP / Windows App 相容性。
- **獨立滾動狀態機 (`ShuttleScrollEngine`)**：支援 7 段速度級距、80ms 啟動緩衝防抖、加減速平滑過渡與跨零點即時方向反轉。
- **圖形化偏好設定 (`SettingsView`)**：
  - 支援 Profile 新增、刪除、拖曳排序與自動定位當前作用中設定檔。
  - 支援應用程式名稱與 `bundleIdentifier` 匹配，並提供「從執行中程式加入」與「瀏覽...」選取器。
  - 原生單鍵點擊快捷鍵錄製器 (`KeyRecorder`)，完整支援 `+`、`Esc`、`Numpad Enter`、`F1`–`F20` 與 macOS 符號顯示。
  - 選配「滑鼠懸停優先 (Hover Priority)」開關，支援雙螢幕游標懸停切換 Profile 與按鍵前自動聚焦目標視窗。
- **版本追蹤與單元測試**：拆分 `MacShuttleCore` 函式庫並建立 `MacShuttleTests`（8 項 `XCTest` 測試），於 Menu Bar 選單與偏好設定視窗顯示版本資訊。
