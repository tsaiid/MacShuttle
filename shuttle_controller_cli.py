import hid
import time
import subprocess  # 用於執行 AppleScript
from pynput.mouse import Controller as MouseController
from pynput.keyboard import Controller as KeyboardController, Key
from AppKit import NSWorkspace

# ================= 硬體設定區 =================

VID = 0x0b33
PID = 0x0030

# Byte 索引 (根據先前的診斷結果)
SHUTTLE_INDEX = 0
JOG_INDEX = 1

# 預設按鍵位置
BUTTON_LOW_INDEX = 3   # 控制按鍵 1-8
BUTTON_HIGH_INDEX = 4  # 控制按鍵 9-15

# ================= 使用者設定區 =================

# 轉盤速度映射 (單位: 秒)
SPEED_MAP = {
    1: 0.8, 2: 0.6, 3: 0.333, 4: 0.2, 5: 0.1, 6: 0.05, 7: 0.02
}

# Mac 硬體鍵碼表 (Key Code) - 用於模擬最底層的按鍵訊號，解決 RDP 不吃字元的問題
MAC_KEY_CODES = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 36, "escape": 53,
    "down": 125, "up": 126, "left": 123, "right": 124
}

# 定義按鍵功能 (對應 Windows App)
# 這裡定義你希望送出的 "字元"，程式會自動查上面的表轉成 code
BUTTON_MAP_WINDOWS = {
    1: "q", 2: "7", 3: "5", 4: "6", 5: "d",
    6: "8", 7: "1", 8: "9", 9: "4", 10: "x",
    11: "f", 13: "w", 14: "o", 15: "down"
}

# ================= 核心邏輯 =================

mouse = MouseController()
keyboard = KeyboardController()
current_app = ""

# 狀態變數
last_shuttle_val = 0
shuttle_active = False
next_scroll_time = 0
last_jog_val = None
last_button_mask = 0
last_raw_data = None

def get_active_app():
    """獲取當前 App 名稱"""
    try:
        app = NSWorkspace.sharedWorkspace().activeApplication()
        return app.get('NSApplicationName', "Unknown")
    except:
        return "Unknown"

def to_signed(n):
    return n - 256 if n > 127 else n

def perform_scroll(direction, multiplier):
    dy = -1 if direction > 0 else 1
    mouse.scroll(0, dy * multiplier)

def perform_key(key_def):
    """執行按鍵 (使用 AppleScript Key Code 強制注入)"""
    print(f"   └── 嘗試執行按鍵: {key_def}")

    # 1. 嘗試轉換為 Mac Key Code (最底層模擬)
    key_code = None
    if isinstance(key_def, str) and key_def.lower() in MAC_KEY_CODES:
        key_code = MAC_KEY_CODES[key_def.lower()]
    elif key_def == Key.down: # 兼容舊設定
        key_code = 125

    if key_code is not None:
        try:
            # 使用 key code 指令，這比 keystroke 更容易穿透 RDP
            cmd = f'tell application "System Events" to key code {key_code}'
            subprocess.run(["osascript", "-e", cmd], check=False)
            print(f"      🍎 AppleScript (Key Code {key_code}) 發送成功")
            return
        except Exception as e:
            print(f"      ⚠️ AppleScript 執行失敗: {e}")

    # 2. Fallback: 如果找不到 Code 或執行失敗，回退到 pynput
    try:
        print("      ⚠️ 無法使用 Key Code，嘗試使用 pynput...")
        if key_def == "down" or key_def == Key.down:
             target_key = Key.down
        else:
             target_key = key_def

        if target_key:
            keyboard.press(target_key)
            time.sleep(0.15)
            keyboard.release(target_key)
    except Exception as e:
        print(f"   ❌ 按鍵錯誤: {e}")

def detect_button_bytes(data):
    """診斷用：偵測哪些 Byte 發生了變化 (排除 Shuttle/Jog)"""
    global last_raw_data
    if last_raw_data is None:
        last_raw_data = list(data)
        return
    for i in range(2, min(len(data), 8)):
        if data[i] != last_raw_data[i]:
            print(f"🔍 診斷: Byte {i} 數值改變 -> {data[i]} (0x{data[i]:02x})")
    last_raw_data = list(data)

def handle_buttons(data):
    """處理按鍵邏輯"""
    global last_button_mask
    if len(data) <= BUTTON_HIGH_INDEX: return

    try:
        current_mask = (data[BUTTON_HIGH_INDEX] << 8) | data[BUTTON_LOW_INDEX]
    except IndexError:
        return

    pressed_mask = current_mask & ~last_button_mask
    last_button_mask = current_mask

    if pressed_mask == 0: return

    # App 判定邏輯
    target_apps = ["Windows App", "Microsoft Remote Desktop", "WindowsApp"]
    is_target_app = any(app in current_app for app in target_apps)

    print(f"🔘 偵測到按鍵訊號 (Mask: {bin(pressed_mask)})")

    for i in range(16):
        if (pressed_mask >> i) & 1:
            button_id = i + 1
            print(f"   ▶ 按下按鈕 ID: {button_id}")

            if is_target_app:
                print(f"   ✅ App 符合 ({current_app})，準備發送按鍵...")
                action = BUTTON_MAP_WINDOWS.get(button_id)
                if action:
                    perform_key(action)
                else:
                    print(f"   ⚠️ ID {button_id} 在設定表中未定義功能")
            else:
                print(f"   ⛔ App 不符合 (目前: {current_app})，略過按鍵功能")

def handle_shuttle(value):
    global shuttle_active, next_scroll_time, last_shuttle_val
    s_val = to_signed(value)
    last_shuttle_val = s_val

    if s_val == 0:
        shuttle_active = False
        return

    target_apps = ["Windows App", "Microsoft Remote Desktop", "WindowsApp"]
    is_target_app = any(app in current_app for app in target_apps)

    shuttle_active = True
    abs_val = abs(s_val)
    interval = SPEED_MAP.get(abs_val, 0.1)

    if time.time() >= next_scroll_time:
        multiplier = 2 if is_target_app else 1
        perform_scroll(s_val, multiplier)
        next_scroll_time = time.time() + interval

def handle_jog(current_val):
    global last_jog_val
    if last_jog_val is None:
        last_jog_val = current_val
        return

    diff = current_val - last_jog_val
    if diff > 127: diff -= 256
    elif diff < -127: diff += 256
    last_jog_val = current_val

    if diff == 0: return

    direction = 1 if diff > 0 else -1
    steps = abs(diff)
    for _ in range(steps):
        perform_scroll(direction, 3)

def main():
    global current_app, shuttle_active, last_shuttle_val
    print("啟動 ShuttlePro v2 控制器 (Key Code 模式)...")
    print("---------------------------------------------------")
    print("💡 操作說明:")
    print("1. 請先點擊你的 'Windows App' 視窗。")
    print("2. 按下按鍵，現在使用 AppleScript 'key code' 發送硬體訊號。")
    print("---------------------------------------------------")

    try:
        h = hid.device()
        h.open(VID, PID)
        h.set_nonblocking(1)
        print(f"✅ 裝置已連接: {h.get_product_string()}")

        app_check_timer = 0

        while True:
            data = h.read(64)
            if data:
                detect_button_bytes(data)
                handle_buttons(data)
                if len(data) > SHUTTLE_INDEX:
                    handle_shuttle(data[SHUTTLE_INDEX])
                if len(data) > JOG_INDEX:
                    handle_jog(data[JOG_INDEX])

            if shuttle_active and last_shuttle_val != 0:
                handle_shuttle(last_shuttle_val)

            if time.time() - app_check_timer > 1.0:
                new_app = get_active_app()
                if new_app != current_app:
                    print(f"🔄 App 切換: [{new_app}]")
                    current_app = new_app
                    shuttle_active = False
                app_check_timer = time.time()

            time.sleep(0.005)

    except IOError:
        print("❌ 找不到裝置")
    except KeyboardInterrupt:
        print("\n程式結束")
    finally:
        try:
            h.close()
        except:
            pass

if __name__ == "__main__":
    main()