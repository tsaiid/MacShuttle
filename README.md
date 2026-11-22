# MacShuttle 🎛️

**MacShuttle** 是一個專為 macOS 設計的開源 **Contour ShuttlePRO v2 / ShuttleXpress / ShuttlePRO v1** 原生 Swift 驅動程式與控制器。

它旨在解決官方驅動程式在現代 macOS 上的相容性問題，提供低資源佔用的 Menu Bar 常駐體驗，以及高度可自訂的「應用程式感知 (App-Aware)」設定檔管理。特別針對 **Windows App (Microsoft Remote Desktop)** 進行了優化，透過混合式按鍵注入（`CGEvent`＋預編譯 `NSAppleScript`）穿透 RDP 遠端桌面。

## ✨ 功能特色

*   **原生 macOS App Bundle**：使用 Swift 與 `IOKit.hid` 底層 API 開發，待機時 CPU 使用率極低，編譯後產生 `MacShuttle.app` 可直接放入 `/Applications`。
*   **智慧 App 感知與多設定檔管理**：支援應用程式名稱與 `Bundle Identifier` 匹配，自動依據前景視窗切換設定檔，並內建跨 Profile App 重疊防呆與衝突提示。
*   **滑鼠懸停優先 (Hover Priority)**：選配支援雙螢幕游標懸停切換設定檔，並在觸發按鍵前自動聚焦目標視窗。
*   **RDP 穿透支援**：無修飾鍵走 `CGEvent` 低延遲通道，複合鍵與大寫字元走背景串行預編譯 `NSAppleScript` 通道，確保 **Windows App** 與 **Microsoft Remote Desktop** 穩定相容。
*   **多段變速滾動引擎 (`ShuttleScrollEngine`)**：針對 Shuttle 外圈提供 7 段變速級距、啟動緩衝防抖、加減速平滑過渡與跨零點即時方向反轉。
*   **圖形化偏好設定介面**：原生 SwiftUI 介面，內建單鍵點擊快捷鍵錄製器 (`KeyRecorder`)、Profile 拖曳排序與熱重載 (Hot-Reload)。

---

## 🚀 編譯、測試與安裝

### 需求
*   macOS 12+
*   Swift 5.5+（Xcode 或 Command Line Tools）

### 編譯與打包 App

```bash
./build_app.sh
```

編譯完成後，會在專案根目錄產生 `MacShuttle.app`，可直接開啟或拖入 `/Applications`：

```bash
open MacShuttle.app
```

### 執行單元測試

```bash
swift test
```

---

## ⚙️ 設定檔

*   第一次執行後，設定檔會自動建立於：
    `~/Library/Application Support/MacShuttle/shuttle_config.json`
*   可透過 Menu Bar 圖示 -> **「偏好設定... (Preferences)」** 進行圖形化設定，或選擇 **「編輯設定檔 (shuttle_config.json)」** 直接編輯。

## ⚠️ 權限說明

首次執行時，macOS 會要求以下權限：
1.  **輸入監控 (Input Monitoring)**：允許讀取 ShuttlePro 的按鍵訊號。
2.  **輔助使用 (Accessibility)**：允許模擬鍵盤按鍵（RDP 穿透所需）。

請在 **「系統設定」->「隱私權與安全性」** 中允許 `MacShuttle`。

---

## 📦 專案結構

*   `Package.swift`：Swift Package Manager 設定。
*   `Sources/MacShuttleCore/`：核心模組（HID 裝置、滾動狀態機、按鍵注入、設定與衝突偵測、SwiftUI 設定介面）。
*   `Sources/MacShuttle/`：應用程式進入點。
*   `Tests/MacShuttleTests/`：`XCTest` 單元測試。
*   `assets/`、`Info.plist`、`VERSION`、`build_app.sh`：App Bundle 資源與打包腳本。

> **關於舊版 Python 原型**：早期原型開發用的 Python 版本已封存於 `archive/python-version` 分支與 `legacy-python-final` Tag，主線目前專注於維護原生 Swift 版本。

## 📝 License

MIT License
