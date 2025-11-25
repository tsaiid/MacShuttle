# MacShuttle 🎛️

**MacShuttle** 是一個專為 macOS 設計的開源 **Contour ShuttlePro v2** 驅動程式與控制器，完全使用 Python 編寫。

它旨在解決官方驅動程式在現代 macOS 上的相容性問題，並提供高度可自訂的「應用程式感知 (App-Aware)」功能。特別針對 **Windows App (Microsoft Remote Desktop)** 進行了優化，透過底層硬體訊號模擬 (AppleScript Key Codes) 穿透 RDP 遠端桌面，解決一般軟體無法控制遠端視窗的痛點。

## ✨ 功能特色

* **Menu Bar 常駐**：輕量級背景執行，透過選單列圖示管理狀態，不佔用 Dock 空間。
* **智慧 App 感知**：自動偵測前景視窗，根據不同 App (如 Chrome, Final Cut Pro, Windows App) 自動切換對應的設定檔 (Profile)。
* **RDP 穿透支援**：使用 AppleScript `key code` 發送底層訊號，完美支援 **Windows App** 與 **Microsoft Remote Desktop**，讓您在 Mac 上用 ShuttlePro 控制遠端的 Windows。
* **原生設定介面**：無需手動編輯 JSON，透過 macOS 原生對話框 (AppleScript Dialogs) 即可快速設定按鍵與滾動速度。
* **熱插拔支援**：USB 拔除後自動進入待機，重新插入後自動恢復連線。
* **多段變速控制**：針對 Shuttle (外圈) 支援 7 段變速設定，可針對不同 App 微調滾動手感。
* **熱重載 (Hot-Reload)**：修改設定檔後無需重啟程式，自動生效。

## 🛠️ 安裝與需求

本專案建議使用 [uv](https://github.com/astral-sh/uv) 進行 Python 環境與相依性管理，確保環境乾淨且快速。

### 1. 下載專案

```bash
git clone https://github.com/yourusername/MacShuttle.git
cd MacShuttle
```

### 2. 安裝依賴

使用 `uv` 自動建立虛擬環境並安裝所需套件：

```bash
uv sync
```

或者，如果您使用傳統的 `pip`：

```bash
pip install hidapi rumps pynput pyobjc-framework-Cocoa
```

### 3. 系統權限設定 (重要！)

由於此程式需要讀取 USB HID 裝置並模擬鍵盤輸入，首次執行時 macOS 會要求權限。請務必在 **「系統設定」->「隱私權與安全性」** 中開啟：

1.  **輸入監控 (Input Monitoring)**：允許讀取 ShuttlePro 的按鍵訊號。
2.  **輔助使用 (Accessibility)**：允許模擬鍵盤按鍵與 AppleScript 控制。

## 🚀 使用方法

### 啟動程式

在專案目錄下執行：

```bash
uv run mac_shuttle.py
```

啟動後，macOS 選單列右上角會出現 `🎛️` 圖示。

### 操作說明

點擊選單列圖示即可進行操作：

* **設定當前 Profile 的 App**：將目前正在使用的 App 加入到設定檔中。
* **按鍵設定**：點選對應的 Button ID，輸入您想模擬的按鍵 (例如 `q`, `enter`, `command+c`)。
* **速度設定**：調整外圈轉盤在不同角度 (Level 1-7) 下的觸發頻率 (毫秒)。數字越小滾動越快。

## ⚙️ 設定檔說明

程式會自動在同目錄下產生 `shuttle_config.json`。您可以透過 Menu Bar 的「開啟設定檔」直接編輯。

**設定檔結構範例：**

```json
{
    "profiles": [
        {
            "name": "Windows Remote",
            "apps": ["Windows App", "Microsoft Remote Desktop"],
            "speeds": [800, 600, 333, 200, 100, 50, 20],
            "buttons": {
                "1": "command+c",
                "13": "enter",
                "15": "down"
            }
        },
        {
            "name": "Default (Global)",
            "apps": ["*"],
            "speeds": [500, 300, 150, 80, 40, 20, 10],
            "buttons": {}
        }
    ]
}
```

* **apps**: 目標應用程式名稱列表 (支援模糊比對)。`"*"` 代表預設設定檔。
* **buttons**: 對應 ShuttlePro 上的按鍵 ID (1-15)。支援 `command+t` 等組合鍵。
* **speeds**: 定義外圈轉動時，觸發滾動/按鍵的時間間隔 (毫秒)。

## ⚠️ 常見問題

**Q: 為什麼在 Windows App 中按鍵沒反應？**
A: 請確認您的終端機 (如 iTerm2 或 Terminal) 已獲得 **「輔助使用」** 權限。Windows App 需要更底層的 AppleScript Key Code 訊號，這需要較高的權限。

**Q: 程式顯示「找不到裝置」？**
A: 請確認 ShuttlePro v2 已插入 USB，且沒有其他驅動程式 (如 Contour 官方驅動或 Karabiner) 正在獨佔該裝置。您可以嘗試點擊選單中的「重新連接裝置」。

## 📝 License

MIT License