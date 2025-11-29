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
# 引入必要的 PyObjC 工具，用於將背景執行緒的操作轉發回主執行緒
from PyObjCTools.AppHelper import callAfter

# ================= 常數設定 =================

VID = 0x0b33
PID = 0x0030

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS_DIR = os.path.join(SCRIPT_DIR, "assets")
CONFIG_FILE = os.path.join(SCRIPT_DIR, "shuttle_config.json")

ICON_ACTIVE = os.path.join(ASSETS_DIR, "icon-active-Template.png")
ICON_INACTIVE = os.path.join(ASSETS_DIR, "icon-inactive-Template.png")
ICON_DISCONNECTED = os.path.join(ASSETS_DIR, "icon-disconnected-Template.png")

SHUTTLE_INDEX = 0
JOG_INDEX = 1
BUTTON_LOW_INDEX = 3
BUTTON_HIGH_INDEX = 4

# 新版預設設定
DEFAULT_CONFIG = {
    "profiles": [
        {
            "name": "Windows Remote",
            "apps": ["Windows App", "Microsoft Remote Desktop", "WindowsApp", "rdp"],
            "speeds": [800, 600, 333, 200, 100, 50, 20],
            "buttons": {
                "1": "q", "2": "7", "3": "5", "4": "6", "5": "d",
                "6": "8", "7": "1", "8": "9", "9": "4", "10": "x",
                "11": "f", "12": "", "13": "w", "14": "o", "15": "down"
            }
        },
        {
            "name": "Chrome / Browser",
            "apps": ["Google Chrome", "Safari", "Microsoft Edge", "Arc"],
            "speeds": [500, 300, 150, 80, 40, 20, 10],
            "buttons": {
                "1": "command+t",
                "2": "command+w",
                "3": "command+r",
                "13": "space"
            }
        },
        {
            "name": "Default (Global)",
            "apps": ["*"],
            "speeds": [800, 600, 333, 200, 100, 50, 20],
            "buttons": {}
        }
    ]
}

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

def load_config_safe():
    if not os.path.exists(CONFIG_FILE):
        save_config_safe(DEFAULT_CONFIG)
        return DEFAULT_CONFIG
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            config = json.load(f)
            if "profiles" not in config:
                new_config = {"profiles": DEFAULT_CONFIG["profiles"]}
                os.rename(CONFIG_FILE, CONFIG_FILE + ".bak")
                save_config_safe(new_config)
                return new_config
            return config
    except Exception as e:
        print(f"❌ Config Error: {e}")
        return DEFAULT_CONFIG

def save_config_safe(config):
    try:
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        return True
    except Exception as e:
        print(f"Save Error: {e}")
        return False

# ================= 主控制器 =================

class ShuttleController(rumps.App):
    def __init__(self):
        init_icon = None
        init_title = "🎛️"

        # 啟動時先檢查一次 Icon 狀態
        if os.path.exists(ICON_DISCONNECTED):
            init_icon = ICON_DISCONNECTED
            init_title = None

        super(ShuttleController, self).__init__("MacShuttle", title=init_title, icon=init_icon, quit_button=None)

        self.config = load_config_safe()

        # 狀態變數
        self.is_running = True
        self.is_enabled = True
        self.device = None

        # 記錄上一次的連線狀態，用於比較是否需要更新 UI
        self.last_device_connected = False

        self.mouse = MouseController()
        self.keyboard = KeyboardController()
        self.current_app = ""
        self.active_profile = None

        self.last_shuttle_val = 0
        self.shuttle_active = False
        self.next_scroll_time = 0
        self.last_jog_val = None
        self.last_button_mask = 0
        self.last_config_mtime = 0

        self.btn_menu_items = []
        self.speed_menu_items = []

        self.build_menu()

        # 初始 UI 更新
        self.update_icon()

        # 啟動背景執行緒 (只處理 HID 邏輯)
        self.thread = threading.Thread(target=self.run_logic_loop)
        self.thread.daemon = True
        self.thread.start()

    @rumps.timer(1.0)
    def watchdog(self, _):
        """
        [主執行緒 Watchdog]
        負責所有週期性的 UI 更新與 App 檢查。
        替代原本在 run_logic_loop 裡的 UI 操作，避免 Crash。
        """
        # 1. 檢查設定檔變更
        self.check_config_file_changes()

        # 2. 檢查連線狀態是否改變 -> 更新 Icon
        is_connected = (self.device is not None)
        if is_connected != self.last_device_connected:
            self.last_device_connected = is_connected
            self.update_connection_ui()
            self.update_icon()

        # 3. 檢查目前 App -> 更新 Menu 文字
        new_app = self.get_active_app()
        ignore_apps = ["System Events", "loginwindow", "Control Center", "Notification Center"]

        if new_app != self.current_app and new_app not in ignore_apps:
            self.current_app = new_app
            self.shuttle_active = False # 切換軟體時重置滾動
            self.update_active_profile()

    def update_connection_ui(self):
        """更新連線狀態的 Menu 項目 (主執行緒)"""
        if self.device:
            try:
                prod = self.device.get_product_string()
                self.menu["狀態: 未連接"].title = f"已連接: {prod}"
            except:
                self.menu["狀態: 未連接"].title = "已連接: Unknown"
        else:
            self.menu["狀態: 未連接"].title = "狀態: 找不到裝置"

    def update_icon(self):
        """更新 Menu Bar 圖示狀態"""
        # 注意: 這裡的邏輯只讀取狀態，不執行耗時操作
        if not self.device:
            if os.path.exists(ICON_DISCONNECTED):
                self.icon = ICON_DISCONNECTED
                self.title = None
                self.template = True
            else:
                self.icon = None
                self.title = "⚠️"
        elif not self.is_enabled:
            if os.path.exists(ICON_INACTIVE):
                self.icon = ICON_INACTIVE
                self.title = None
                self.template = True
            else:
                self.icon = None
                self.title = "⚪"
        else:
            if os.path.exists(ICON_ACTIVE):
                self.icon = ICON_ACTIVE
                self.title = None
                self.template = True
            else:
                self.icon = None
                self.title = "🎛️"

    def build_menu(self):
        self.menu.clear()
        self.btn_menu_items = []
        self.speed_menu_items = []

        self.menu.add(rumps.MenuItem("狀態: 未連接", callback=None))
        self.menu.add(rumps.MenuItem("當前 App: 未知", callback=None))
        self.menu.add(rumps.MenuItem("使用設定: 無", callback=None))
        self.menu.add(rumps.separator)

        self.menu.add(rumps.MenuItem("啟用中 (Enabled)", callback=self.toggle_active, key="e"))
        self.menu.get("啟用中 (Enabled)").state = True

        self.menu.add(rumps.separator)

        self.menu.add(rumps.MenuItem("設定當前 Profile 的 App...", callback=self.ui_set_apps))

        btn_menu = rumps.MenuItem("按鍵設定 (Current Profile)")
        for i in range(1, 16):
            item = rumps.MenuItem(f"Button {i:02d}", callback=self.make_set_button_callback(str(i)))
            self.btn_menu_items.append(item)
            btn_menu.add(item)
        self.menu.add(btn_menu)

        speed_menu = rumps.MenuItem("速度設定 (Current Profile)")
        for i in range(7):
            item = rumps.MenuItem(f"Level {i+1}", callback=self.make_set_speed_callback(i))
            self.speed_menu_items.append(item)
            speed_menu.add(item)
        self.menu.add(speed_menu)

        self.menu.add(rumps.separator)

        self.menu.add(rumps.MenuItem("開啟設定檔 (JSON)...", callback=self.open_json_file))
        self.menu.add(rumps.MenuItem("強制重新載入 (Reload)", callback=self.manual_reload))
        self.menu.add(rumps.MenuItem("重新連接裝置", callback=self.trigger_reconnect))
        self.menu.add(rumps.separator)
        self.menu.add(rumps.MenuItem("離開 (Quit)", callback=rumps.quit_application))

    def update_menu_state(self):
        self.menu["當前 App: 未知"].title = f"當前 App: {self.current_app}"

        if self.active_profile:
            p_name = self.active_profile.get("name", "Unknown")
            self.menu["使用設定: 無"].title = f"使用設定: {p_name}"

            buttons = self.active_profile.get("buttons", {})
            for i, item in enumerate(self.btn_menu_items):
                btn_id = str(i + 1)
                key_val = buttons.get(btn_id, "")
                item.title = f"Button {btn_id.zfill(2)}: {key_val}" if key_val else f"Button {btn_id.zfill(2)}: (無)"

            speeds = self.active_profile.get("speeds", [])
            if len(speeds) >= 7:
                for i, item in enumerate(self.speed_menu_items):
                    val = speeds[i]
                    item.title = f"Level {i+1} (目前: {val}ms)"
        else:
            self.menu["使用設定: 無"].title = "使用設定: 無 (未匹配)"
            for i, item in enumerate(self.btn_menu_items):
                item.title = f"Button {i+1:02d}: (無)"
            for i, item in enumerate(self.speed_menu_items):
                item.title = f"Level {i+1}"

    def update_active_profile(self):
        if not self.config or "profiles" not in self.config:
            self.active_profile = None
            self.update_menu_state()
            return

        matched_profile = None
        for profile in self.config["profiles"]:
            apps = profile.get("apps", [])
            if "*" in apps: continue
            if any(target in self.current_app for target in apps):
                matched_profile = profile
                break

        if not matched_profile:
            for profile in self.config["profiles"]:
                if "*" in profile.get("apps", []):
                    matched_profile = profile
                    break

        if matched_profile != self.active_profile:
            self.active_profile = matched_profile
            self.update_menu_state()

    def make_set_button_callback(self, btn_id):
        def callback(sender):
            self.ui_set_button(btn_id, sender)
        return callback

    def make_set_speed_callback(self, index):
        def callback(sender):
            self.ui_set_speed(index, sender)
        return callback

    # --- AppleScript & UI Dialogs ---

    def show_input_dialog(self, title, message, default_text=""):
        msg = message.replace('"', '\\"')
        default = default_text.replace('"', '\\"')
        title_text = title.replace('"', '\\"')
        # 修正: 加入 cancel button "Cancel" 以正確處理取消動作
        script = f'''
        tell application "System Events"
            activate
            set theResult to display dialog "{msg}" default answer "{default}" with title "{title_text}" buttons {{"Cancel", "OK"}} default button "OK" cancel button "Cancel"
            text returned of theResult
        end tell
        '''
        try:
            result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.strip()
            return None
        except:
            return None

    def show_confirmation_dialog(self, title, message):
        msg = message.replace('"', '\\"')
        title_text = title.replace('"', '\\"')
        # 修正: 加入 cancel button "取消"
        script = f'''
        tell application "System Events"
            activate
            set theResult to display dialog "{msg}" with title "{title_text}" buttons {{"取消", "建立"}} default button "建立" cancel button "取消"
            button returned of theResult
        end tell
        '''
        try:
            result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
            return "建立" in result.stdout
        except:
            return False

    def show_alert(self, title, message):
        msg = message.replace('"', '\\"')
        title_text = title.replace('"', '\\"')
        script = f'''
        tell application "System Events"
            activate
            display alert "{title_text}" message "{msg}" as warning buttons {{"OK"}} default button "OK"
        end tell
        '''
        try:
            subprocess.run(['osascript', '-e', script], check=False)
        except:
            pass

    def show_notification(self, title, subtitle, message):
        t = title.replace('"', '\\"')
        s = subtitle.replace('"', '\\"')
        m = message.replace('"', '\\"')
        script = f'display notification "{m}" with title "{t}" subtitle "{s}"'
        try:
            subprocess.run(['osascript', '-e', script], check=False)
        except:
            pass

    # --- 邏輯操作 (這些會開 Thread，所以 UI 更新要用 callAfter) ---

    def create_new_profile_for_current_app(self, app_name_snapshot):
        target_app = app_name_snapshot
        if not target_app or target_app == "Unknown":
            return None

        print(f"正在為 {target_app} 建立新設定檔...")
        default_speeds = list(DEFAULT_CONFIG["profiles"][-1]["speeds"])
        new_profile = {
            "name": target_app,
            "apps": [target_app],
            "speeds": default_speeds,
            "buttons": {}
        }
        self.config["profiles"].insert(0, new_profile)
        if save_config_safe(self.config):
            # 重要：使用 callAfter 確保在主執行緒更新
            callAfter(self.update_active_profile)
            callAfter(self.show_notification, "MacShuttle", "設定檔建立成功", f"已為 {target_app} 建立設定檔")
            return new_profile
        else:
            callAfter(self.show_alert, "錯誤", "無法寫入設定檔，請檢查權限。")
            return None

    def ui_set_apps(self, sender):
        current_app_snapshot = self.current_app
        threading.Thread(target=self._thread_set_apps_logic, args=(current_app_snapshot,)).start()

    def _thread_set_apps_logic(self, app_name_snapshot):
        target_profile = self.active_profile
        is_default = False
        if target_profile:
            if "*" in target_profile.get("apps", []):
                is_default = True

        if not target_profile or is_default:
            msg = f"應用程式: {app_name_snapshot}\\n目前使用預設設定 (Default)。\\n\\n是否要為此 App 建立專屬設定檔？"
            if self.show_confirmation_dialog("建立新設定檔", msg):
                self.create_new_profile_for_current_app(app_name_snapshot)
            return

        current = ",".join(target_profile.get("apps", []))
        new_val = self.show_input_dialog(
            title=f"設定 App ({target_profile.get('name')})",
            message="請輸入目標 App 名稱 (以逗號分隔)",
            default_text=current
        )

        if new_val is not None:
            new_list = [x.strip() for x in new_val.split(",") if x.strip()]
            target_profile["apps"] = new_list
            if save_config_safe(self.config):
                callAfter(self.update_active_profile)
                callAfter(self.show_notification, "MacShuttle", "儲存成功", "App 清單已更新")

    def ui_set_button(self, btn_id, sender):
        current_app_snapshot = self.current_app
        threading.Thread(target=self._thread_set_button_logic, args=(btn_id, sender, current_app_snapshot)).start()

    def _thread_set_button_logic(self, btn_id, sender, app_name_snapshot):
        target_profile = self.active_profile
        is_default = False
        if target_profile and "*" in target_profile.get("apps", []):
            is_default = True

        if not target_profile: return

        current = target_profile["buttons"].get(btn_id, "")
        p_name = target_profile.get("name")
        new_val = self.show_input_dialog(
            title=f"設定 Button {btn_id} ({p_name})",
            message=f"請輸入按鍵 (例如: q, enter, command+c)\\n留空則清除功能。",
            default_text=current
        )
        if new_val is not None:
            target_profile["buttons"][btn_id] = new_val.strip()
            if save_config_safe(self.config):
                callAfter(self.update_menu_state)
                callAfter(self.show_notification, "MacShuttle", "儲存成功", f"Button {btn_id} 已更新")

    def ui_set_speed(self, index, sender):
        current_app_snapshot = self.current_app
        threading.Thread(target=self._thread_set_speed_logic, args=(index, sender, current_app_snapshot)).start()

    def _thread_set_speed_logic(self, index, sender, app_name_snapshot):
        target_profile = self.active_profile
        if not target_profile: return
        current = str(target_profile["speeds"][index])
        new_val = self.show_input_dialog(
            title=f"設定速度 Level {index+1}",
            message=f"請輸入滾動間隔 (毫秒)\\n當前設定檔: {target_profile.get('name')}",
            default_text=current
        )
        if new_val is not None:
            try:
                val = int(new_val.strip())
                target_profile["speeds"][index] = val
                if save_config_safe(self.config):
                    callAfter(self.update_menu_state)
                    callAfter(self.show_notification, "MacShuttle", "儲存成功", "速度已更新")
            except ValueError:
                callAfter(self.show_alert, "錯誤", "請輸入有效的整數數字")

    def check_config_file_changes(self):
        """檢查設定檔是否有外部變更 (由 watchdog 呼叫)"""
        if not os.path.exists(CONFIG_FILE): return
        try:
            mtime = os.stat(CONFIG_FILE).st_mtime
            if self.last_config_mtime == 0:
                self.last_config_mtime = mtime
                return
            if mtime > self.last_config_mtime:
                print("偵測到設定檔變更，正在重新載入...")
                self.last_config_mtime = mtime
                new_config = load_config_safe()
                if new_config:
                    self.config = new_config
                    self.update_active_profile()
                    self.show_notification("MacShuttle", "設定已重載", "JSON 檔案變更已自動套用")
        except Exception: pass

    def manual_reload(self, sender):
        new_config = load_config_safe()
        if new_config:
            self.config = new_config
            self.update_active_profile()
            self.show_notification("MacShuttle", "重載成功", "設定已更新")

    def open_json_file(self, sender):
        if not os.path.exists(CONFIG_FILE):
            save_config_safe(DEFAULT_CONFIG)
        subprocess.run(["open", "-e", CONFIG_FILE])

    def toggle_active(self, sender):
        sender.state = not sender.state
        self.is_enabled = not self.is_enabled
        self.update_icon()
        print(f"功能開關: {self.is_enabled}")

    def trigger_reconnect(self, sender):
        """手動觸發重連 (只做標記，由背景 thread 執行)"""
        if self.device:
            try: self.device.close()
            except: pass
            self.device = None
        # Background loop will detect self.device is None and try to reconnect

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
        if not key_def: return
        print(f"   └── 執行按鍵: {key_def}")

        key_code = None
        key_lower = key_def.lower()
        modifiers = []
        base_key = key_lower

        if "+" in key_lower:
            parts = key_lower.split("+")
            base_key = parts[-1]
            if "command" in parts or "cmd" in parts: modifiers.append("command down")
            if "shift" in parts: modifiers.append("shift down")
            if "control" in parts or "ctrl" in parts: modifiers.append("control down")
            if "option" in parts or "alt" in parts: modifiers.append("option down")

        if base_key in MAC_KEY_CODES:
            key_code = MAC_KEY_CODES[base_key]
        elif key_def == Key.down or key_def == "Key.down":
            key_code = 125

        if key_code is not None:
            try:
                mod_str = ""
                if modifiers:
                    mod_str = " using {" + ", ".join(modifiers) + "}"
                cmd = f'tell application "System Events" to key code {key_code}{mod_str}'
                subprocess.run(["osascript", "-e", cmd], check=False)
                return
            except Exception: pass

        try:
            target_key = Key.down if (base_key == "down") else key_def
            if target_key:
                self.keyboard.press(target_key)
                time.sleep(0.15)
                self.keyboard.release(target_key)
        except Exception: pass

    def handle_buttons(self, data):
        if len(data) <= BUTTON_HIGH_INDEX: return
        try:
            current_mask = (data[BUTTON_HIGH_INDEX] << 8) | data[BUTTON_LOW_INDEX]
        except IndexError: return

        pressed_mask = current_mask & ~self.last_button_mask
        self.last_button_mask = current_mask

        if pressed_mask == 0: return

        if not self.active_profile: return

        for i in range(16):
            if (pressed_mask >> i) & 1:
                action = self.active_profile["buttons"].get(str(i + 1))
                if action: self.perform_key(action)

    def handle_shuttle(self, value):
        s_val = self.to_signed(value)
        self.last_shuttle_val = s_val

        if s_val == 0:
            self.shuttle_active = False
            return

        if not self.active_profile: return

        self.shuttle_active = True
        abs_val = abs(s_val)

        speeds = self.active_profile.get("speeds", DEFAULT_CONFIG["profiles"][-1]["speeds"])
        idx = min(max(abs_val - 1, 0), 6)
        interval = speeds[idx] / 1000.0

        multiplier = 2

        if time.time() >= self.next_scroll_time:
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

    def _connect_hid_backend(self):
        """[背景執行緒] 嘗試連接 HID 裝置"""
        try:
            self.device = hid.device()
            self.device.open(VID, PID)
            self.device.set_nonblocking(1)
            print(f"✅ HID 裝置已連接")
        except IOError:
            self.device = None

    def run_logic_loop(self):
        """
        [背景執行緒] 主邏輯迴圈
        只負責 HID I/O，不碰 UI
        """
        while self.is_running:
            if not self.is_enabled:
                time.sleep(1)
                continue

            # 裝置連線邏輯
            if not self.device:
                self._connect_hid_backend()
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
                print(f"Read Error: {e}")
                try: self.device.close()
                except: pass
                self.device = None
                time.sleep(1)
                continue

            time.sleep(0.005)

if __name__ == "__main__":
    app = ShuttleController()
    app.run()