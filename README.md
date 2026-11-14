# MacShuttle 🎛️

**MacShuttle** 是一個專為 macOS 設計的開源 **Contour ShuttlePro v2** 驅動程式與控制器。

專案包含兩個版本：
1.  **Native Version (Swift)**: 推薦使用。高效能、原生 Menu Bar App、原生通知與系統整合。
2.  **Python Version (Legacy)**: 原型開發版本，適合開發者研究或自訂邏輯。

它旨在解決官方驅動程式在現代 macOS 上的相容性問題，並提供高度可自訂的「應用程式感知 (App-Aware)」功能。特別針對 **Windows App (Microsoft Remote Desktop)** 進行了優化，透過底層硬體訊號模擬 (AppleScript Key Codes) 穿透 RDP 遠端桌面。

## 📂 專案結構

*   `native_version/`: Swift 原生版本 (正式版)。
*   `python_version/`: Python 舊版本 (開發用)。

---

## 🚀 Native Version (推薦)

位於 `native_version/` 目錄。這是一個標準的 Swift macOS App。

### 特色
*   **原生 App Bundle**: 編譯後產生 `MacShuttle.app`，可直接放入 `/Applications`。
*   **極低資源佔用**: 使用 IOKit 底層 API，待機時 CPU 使用率 0%。
*   **App 感知**: 自動切換設定檔。
*   **原生 UI**: 使用系統 Menu Bar 與原生對話框。

### 如何編譯與安裝

1.  進入目錄：
    ```bash
    cd native_version
    ```

2.  執行編譯腳本：
    ```bash
    ./build_app.sh
    ```

3.  安裝：
    編譯完成後，會產生 `MacShuttle.app`。您可以將其拖入「應用程式」資料夾。

    ```bash
    open MacShuttle.app
    ```

### 設定檔

*   第一次執行後，設定檔會自動建立於：
    `~/Library/Application Support/MacShuttle/shuttle_config.json`
*   您可以透過 Menu Bar 圖示 -> **「編輯設定檔 (shuttle_config.json)」** 快速開啟編輯，或使用 **「偏好設定... (Preferences)」** 進行圖形化設定。

---

## 🐍 Python Version (Legacy)

位於 `python_version/` 目錄。

### 需求
*   Python 3.10+
*   uv (推薦) 或 pip

### 執行方法

```bash
cd python_version
uv sync
uv run mac_shuttle.py
```

---

## ✨ 功能總覽 (雙版本皆支援)

*   **Menu Bar 常駐**：輕量級背景執行。
*   **智慧 App 感知**：自動偵測前景視窗，根據不同 App (如 Chrome, Final Cut Pro, Windows App) 自動切換設定檔。
*   **RDP 穿透支援**：支援 **Windows App** 與 **Microsoft Remote Desktop**。
*   **多段變速控制**：針對 Shuttle (外圈) 支援 7 段變速設定。
*   **熱重載 (Hot-Reload)**：修改設定檔後無需重啟程式。

## ⚠️ 權限說明

首次執行時，macOS 會要求以下權限：
1.  **輸入監控 (Input Monitoring)**：允許讀取 ShuttlePro 的按鍵訊號。
2.  **輔助使用 (Accessibility)**：允許模擬鍵盤按鍵 (RDP 穿透所需)。

請在 **「系統設定」->「隱私權與安全性」** 中允許 `MacShuttle`。

## 📝 License

MIT License