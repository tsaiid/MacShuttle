import hid
import time
import subprocess
import threading
import rumps
import sys
import os
import json
from pynput.mouse import Controller as MouseController
from pynput.keyboard import Controller as KeyboardController, Key
from AppKit import NSWorkspace

# ================= 常數設定 =================

VID = 0x0b33
PID = 0x0030

# 確保設定檔建立在腳本所在的資料夾，避免找不到
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "shuttle_config.json")

SHUTTLE_INDEX = 0
JOG_INDEX = 1
BUTTON_LOW_INDEX = 3
BUTTON_HIGH_INDEX = 4

# 預設設定 (若無設定檔時自動建立)
DEFAULT_CONFIG = {
    "target_apps": "Windows App, Microsoft Remote Desktop, WindowsApp",
    # 速度設定 (毫秒) Level 1 -> 7
    "speeds": [800, 600, 333, 200, 100, 50, 20],
    # 按鍵對應 (Button ID 1-15)
    "buttons": {
        "1": "q", "2": "7", "3": "5", "4": "6", "5": "d",
        "6": "8", "7": "1", "8": "9", "9": "4", "10": "x",
        "11": "f", "13": "w", "14": "o", "15": "down"
    }
}

# Mac Key Codes 參照表 (不需更動)
MAC_KEY_CODES = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 36, "escape": 53,
    "down": 125, "up": 126, "left": 123, "right": 124, "f1": 122, "f2": 120, "f3": 99,
    "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
    "f11": 103, "f12": 111, "command": 55, "shift": 56, "capslock": 57, "option": 58,
    "control": 59, "right_command": 54, "right_shift": 60, "right_option": 61,
    "right_control": 62, "fn": 63
}

# ================= 設定檔管理 =================

def load_config():
    """讀取設定檔，若不存在則建立預設值"""
    if not os.path.exists(CONFIG_FILE):
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG

    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            config = json.load(f)
            # 確保欄位齊全
            for key, val in DEFAULT_CONFIG.items():
                if key not in config:
                    config[key] = val
            return config
    except Exception as e:
        print(f"讀取設定失敗: {e}")
        return DEFAULT_CONFIG

def save_config(config):
    """儲存設定檔"""
    try:
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
    except Exception as e:
        print(f"儲存設定失敗: {e}")

# ================= 主控制器 (Menu Bar App) =================

class ShuttleController(rumps.App):
    def __init__(self):
        super(ShuttleController, self).__init__("🎛️")

        self.config = load_config() # 初始載入

        self.menu = [
            rumps.MenuItem("狀態: 未連接", callback=None),
            rumps.separator,
            rumps.MenuItem("啟用中 (Enabled)", callback=self.toggle_active),
            rumps.MenuItem("開啟設定檔 (Edit Config)...", callback=self.open_settings),
            rumps.MenuItem("重新載入設定 (Reload)", callback=self.reload_config),
            rumps.MenuItem("重新連接裝置", callback=self.connect_device),
            rumps.separator
        ]

        self.is_running = True
        self.is_enabled = True
        self.device = None

        self.mouse = MouseController()
        self.keyboard = KeyboardController()
        self.current_app = ""

        self.last_shuttle_val = 0
        self.shuttle_active = False
        self.next_scroll_time = 0
        self.last_jog_val = None
        self.last_button_mask = 0

        self.thread = threading.Thread(target=self.run_logic_loop)
        self.thread.daemon = True
        self.thread.start()

        # 嘗試連接
        self.connect_device(None)

    def reload_config(self, sender):
        print("🔄 重新載入設定...")
        self.config = load_config()
        rumps.notification("ShuttlePro", "設定已更新", "新的設定已生效")

    def open_settings(self, sender):
        """直接使用 macOS 預設編輯器開啟 JSON 設定檔"""
        if not os.path.exists(CONFIG_FILE):
            save_config(DEFAULT_CONFIG)

        print(f"開啟設定檔: {CONFIG_FILE}")
        # 使用 'open' 指令呼叫 macOS 預設程式開啟 JSON
        subprocess.run(["open", CONFIG_FILE])

    def toggle_active(self, sender):
        sender.state = not sender.state
        self.is_enabled = not self.is_enabled
        print(f"功能開關: {self.is_enabled}")

    def connect_device(self, sender):
        if self.device:
            try: self.device.close()
            except: pass
            self.device = None
        try:
            self.device = hid.device()
            self.device.open(VID, PID)
            self.device.set_nonblocking(1)
            product = self.device.get_product_string()
            self.title = "🎛️"
            self.menu["狀態: 未連接"].title = f"已連接: {product}"
            print(f"✅ 裝置已連接: {product}")
        except IOError:
            self.title = "⚠️"
            self.menu["狀態: 未連接"].title = "狀態: 找不到裝置"

    def get_active_app(self):
        try:
            app = NSWorkspace.sharedWorkspace().activeApplication()
            return app.get('NSApplicationName', "Unknown")
        except:
            return "Unknown"

    def to_signed(self, n):
        return n - 256 if n > 127 else n

    def perform_scroll(self, direction, multiplier):
        dy = -1 if direction > 0 else 1
        self.mouse.scroll(0, dy * multiplier)

    def perform_key(self, key_def):
        print(f"   └── 執行按鍵: {key_def}")

        key_code = None
        key_lower = key_def.lower() if isinstance(key_def, str) else ""

        # 1. 查找 AppleScript Key Code
        if key_lower in MAC_KEY_CODES:
            key_code = MAC_KEY_CODES[key_lower]
        elif key_def == Key.down or key_def == "Key.down":
            key_code = 125

        if key_code is not None:
            try:
                cmd = f'tell application "System Events" to key code {key_code}'
                subprocess.run(["osascript", "-e", cmd], check=False)
                return
            except Exception as e:
                print(f"      ⚠️ AppleScript 執行失敗: {e}")

        # 2. Fallback pynput
        try:
            target_key = Key.down if (key_lower == "down") else key_def
            if target_key:
                self.keyboard.press(target_key)
                time.sleep(0.15)
                self.keyboard.release(target_key)
        except Exception as e:
            print(f"   ❌ 按鍵錯誤: {e}")

    def handle_buttons(self, data):
        if len(data) <= BUTTON_HIGH_INDEX: return
        try:
            current_mask = (data[BUTTON_HIGH_INDEX] << 8) | data[BUTTON_LOW_INDEX]
        except IndexError:
            return

        pressed_mask = current_mask & ~self.last_button_mask
        self.last_button_mask = current_mask

        if pressed_mask == 0: return

        # 讀取設定中的目標 Apps
        target_str = self.config.get("target_apps", "")
        # 分割字串並去除空白
        target_apps = [x.strip() for x in target_str.split(",") if x.strip()]

        is_target_app = any(app in self.current_app for app in target_apps)

        for i in range(16):
            if (pressed_mask >> i) & 1:
                button_id = str(i + 1)
                if is_target_app:
                    # 從設定讀取按鍵映射
                    btn_map = self.config.get("buttons", {})
                    action = btn_map.get(button_id)
                    if action:
                        self.perform_key(action)

    def handle_shuttle(self, value):
        s_val = self.to_signed(value)
        self.last_shuttle_val = s_val

        if s_val == 0:
            self.shuttle_active = False
            return

        target_str = self.config.get("target_apps", "")
        target_apps = [x.strip() for x in target_str.split(",") if x.strip()]
        is_target_app = any(app in self.current_app for app in target_apps)

        self.shuttle_active = True
        abs_val = abs(s_val)

        # 從設定讀取速度 (注意: 設定是 ms，我們要轉成秒)
        speeds = self.config.get("speeds", DEFAULT_CONFIG["speeds"])
        # abs_val 範圍是 1-7，List 索引是 0-6
        idx = min(max(abs_val - 1, 0), 6)
        interval_ms = speeds[idx]
        interval = interval_ms / 1000.0

        if time.time() >= self.next_scroll_time:
            multiplier = 2 if is_target_app else 1
            self.perform_scroll(s_val, multiplier)
            self.next_scroll_time = time.time() + interval

    def handle_jog(self, current_val):
        if self.last_jog_val is None:
            self.last_jog_val = current_val
            return

        diff = current_val - self.last_jog_val
        if diff > 127: diff -= 256
        elif diff < -127: diff += 256
        self.last_jog_val = current_val

        if diff == 0: return

        direction = 1 if diff > 0 else -1
        steps = abs(diff)
        for _ in range(steps):
            self.perform_scroll(direction, 3)

    def run_logic_loop(self):
        app_check_timer = 0
        while self.is_running:
            if not self.is_enabled:
                time.sleep(1)
                continue

            if not self.device:
                self.connect_device(None)
                if not self.device:
                    time.sleep(2.0)
                    continue

            try:
                data = self.device.read(64)
                if data:
                    self.handle_buttons(data)
                    if len(data) > SHUTTLE_INDEX:
                        self.handle_shuttle(data[SHUTTLE_INDEX])
                    if len(data) > JOG_INDEX:
                        self.handle_jog(data[JOG_INDEX])

                if self.shuttle_active and self.last_shuttle_val != 0:
                    self.handle_shuttle(self.last_shuttle_val)

            except Exception as e:
                print(f"裝置錯誤: {e}")
                try: self.device.close()
                except: pass
                self.device = None
                self.title = "⚠️"
                self.menu["狀態: 未連接"].title = "狀態: 斷線 (重連中...)"
                time.sleep(1)
                continue

            if time.time() - app_check_timer > 1.0:
                new_app = self.get_active_app()
                if new_app != self.current_app:
                    self.current_app = new_app
                    self.shuttle_active = False
                    # 每次切換 App 時，自動重新讀取一次設定檔，確保設定最新
                    # self.config = load_config()
                app_check_timer = time.time()

            time.sleep(0.005)

if __name__ == "__main__":
    app = ShuttleController()
    app.menu["啟用中 (Enabled)"].state = True
    app.run()