import hid
import time
import subprocess
import threading
import rumps  # 需安裝: pip install rumps
from pynput.mouse import Controller as MouseController
from pynput.keyboard import Controller as KeyboardController, Key
from AppKit import NSWorkspace

# ================= 硬體設定區 =================

VID = 0x0b33
PID = 0x0030

SHUTTLE_INDEX = 0
JOG_INDEX = 1
BUTTON_LOW_INDEX = 3
BUTTON_HIGH_INDEX = 4

# ================= 使用者設定區 =================

SPEED_MAP = {
    1: 0.8, 2: 0.6, 3: 0.333, 4: 0.2, 5: 0.1, 6: 0.05, 7: 0.02
}

MAC_KEY_CODES = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    "tab": 48, "space": 49, "`": 50, "delete": 51, "enter": 36, "escape": 53,
    "down": 125, "up": 126, "left": 123, "right": 124
}

BUTTON_MAP_WINDOWS = {
    1: "q", 2: "7", 3: "5", 4: "6", 5: "d",
    6: "8", 7: "1", 8: "9", 9: "4", 10: "x",
    11: "f", 13: "w", 14: "o", 15: "down"
}

# ================= 核心邏輯類別 =================

class ShuttleController(rumps.App):
    def __init__(self):
        super(ShuttleController, self).__init__("🎛️")
        self.menu = [
            rumps.MenuItem("狀態: 未連接", callback=None),
            rumps.separator,
            rumps.MenuItem("啟用中 (Enabled)", callback=self.toggle_active),
            rumps.MenuItem("重新連接裝置", callback=self.connect_device),
            rumps.separator
        ]

        # 控制變數
        self.is_running = True     # 程式是否在執行
        self.is_enabled = True     # 功能開關
        self.device = None

        # 邏輯變數
        self.mouse = MouseController()
        self.keyboard = KeyboardController()
        self.current_app = ""

        self.last_shuttle_val = 0
        self.shuttle_active = False
        self.next_scroll_time = 0
        self.last_jog_val = None
        self.last_button_mask = 0

        # 啟動背景執行緒
        self.thread = threading.Thread(target=self.run_logic_loop)
        self.thread.daemon = True
        self.thread.start()

        # 初始連接 (不阻塞)
        self.connect_device(None)

    def toggle_active(self, sender):
        sender.state = not sender.state
        self.is_enabled = not self.is_enabled
        print(f"功能開關: {self.is_enabled}")

    def connect_device(self, sender):
        """嘗試連接裝置並更新 UI"""
        if self.device:
            try:
                self.device.close()
            except:
                pass
            self.device = None

        try:
            self.device = hid.device()
            self.device.open(VID, PID)
            self.device.set_nonblocking(1)
            product = self.device.get_product_string()
            self.title = "🎛️" # 正常圖示
            self.menu["狀態: 未連接"].title = f"已連接: {product}"
            print(f"✅ 裝置已連接: {product}")
        except IOError:
            self.title = "⚠️" # 錯誤圖示
            self.menu["狀態: 未連接"].title = "狀態: 找不到裝置"
            # 注意：這裡不 print 錯誤，避免在自動重連迴圈中洗版 Console

    # --- 以下是原本的邏輯函數，搬進 Class 內 ---

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
        print(f"   └── 嘗試執行按鍵: {key_def}")

        key_code = None
        if isinstance(key_def, str) and key_def.lower() in MAC_KEY_CODES:
            key_code = MAC_KEY_CODES[key_def.lower()]
        elif key_def == Key.down:
            key_code = 125

        if key_code is not None:
            try:
                cmd = f'tell application "System Events" to key code {key_code}'
                subprocess.run(["osascript", "-e", cmd], check=False)
                return
            except Exception as e:
                print(f"      ⚠️ AppleScript 執行失敗: {e}")

        try:
            if key_def == "down" or key_def == Key.down:
                target_key = Key.down
            else:
                target_key = key_def
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

        target_apps = ["Windows App", "Microsoft Remote Desktop", "WindowsApp"]
        is_target_app = any(app in self.current_app for app in target_apps)

        for i in range(16):
            if (pressed_mask >> i) & 1:
                button_id = i + 1
                if is_target_app:
                    action = BUTTON_MAP_WINDOWS.get(button_id)
                    if action:
                        self.perform_key(action)

    def handle_shuttle(self, value):
        s_val = self.to_signed(value)
        self.last_shuttle_val = s_val

        if s_val == 0:
            self.shuttle_active = False
            return

        target_apps = ["Windows App", "Microsoft Remote Desktop", "WindowsApp"]
        is_target_app = any(app in self.current_app for app in target_apps)

        self.shuttle_active = True
        abs_val = abs(s_val)
        interval = SPEED_MAP.get(abs_val, 0.1)

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
        """背景執行緒的主迴圈"""
        app_check_timer = 0

        while self.is_running:
            # 如果被停用，稍微休息一下再檢查
            if not self.is_enabled:
                time.sleep(1)
                continue

            # --- 自動重連機制 ---
            if not self.device:
                # 嘗試連接
                self.connect_device(None)
                if not self.device:
                    # 如果還是失敗，等待 2 秒後再試，避免佔用 CPU
                    time.sleep(2.0)
                    continue

            # --- 讀取與處理 ---
            try:
                data = self.device.read(64)
                if data:
                    self.handle_buttons(data)
                    if len(data) > SHUTTLE_INDEX:
                        self.handle_shuttle(data[SHUTTLE_INDEX])
                    if len(data) > JOG_INDEX:
                        self.handle_jog(data[JOG_INDEX])

                # 持續 Shuttle (即使沒有新訊號，只要沒歸零就要持續送出滾動)
                if self.shuttle_active and self.last_shuttle_val != 0:
                    self.handle_shuttle(self.last_shuttle_val)

            except Exception as e:
                # 讀取錯誤（通常是裝置被拔除）
                print(f"裝置讀取錯誤 (斷線): {e}")

                # 安全關閉並將 device 設為 None，觸發下一次迴圈的重連機制
                try:
                    self.device.close()
                except:
                    pass
                self.device = None

                # 更新 UI 狀態
                self.title = "⚠️"
                self.menu["狀態: 未連接"].title = "狀態: 斷線 (嘗試重連中...)"

                # 避免立即重試
                time.sleep(1)
                continue

            # 檢查 App
            if time.time() - app_check_timer > 1.0:
                new_app = self.get_active_app()
                if new_app != self.current_app:
                    self.current_app = new_app
                    self.shuttle_active = False
                app_check_timer = time.time()

            time.sleep(0.005)

if __name__ == "__main__":
    app = ShuttleController()
    app.menu["啟用中 (Enabled)"].state = True # 預設打勾
    app.run()