# Changelog

All notable changes to **MacShuttle** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
