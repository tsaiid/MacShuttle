import hid
import time
from pynput.mouse import Controller as MouseController
from pynput.keyboard import Controller as KeyboardController, Key
from AppKit import NSWorkspace

# ================= 設定區 =================

VID = 0x0b33
PID = 0x0030

# 根據你的數據確認的索引
SHUTTLE_INDEX = 0
JOG_INDEX = 1

# 定義不同軟體的設定
APP_CONFIG = {
    # 設定 Chrome: 外圈滾動網頁，內圈切換分頁
    "Google Chrome": {
        "shuttle_mode": "scroll",
        "scroll_speed": 1.0,
        "jog_mode": "key",
        # 內圈往左切上一分頁，往右切下一分頁
        "jog_left": { "key": Key.tab, "modifiers": [Key.ctrl, Key.shift] },
        "jog_right": { "key": Key.tab, "modifiers": [Key.ctrl] }
    },
    # 設定 Final Cut Pro (或 Premiere): 剪輯專用
    "Final Cut Pro": {
        "shuttle_mode": "key",
        # 外圈模擬 J (倒轉) / L (快進)
        "key_left": "j",
        "key_right": "l",

        "jog_mode": "key",
        # 內圈模擬左右鍵 (逐格移動)
        "jog_left": { "key": Key.left, "modifiers": [] },
        "jog_right": { "key": Key.right, "modifiers": [] }
    },
    # 預設設定
    "default": {
        "shuttle_mode": "scroll",
        "scroll_speed": 1.0, # 數字越小滾越慢
        "jog_mode": "scroll", # 內圈也當滾輪用 (精細微調)
        "jog_scroll_multiplier": 5
    }
}

# 轉盤速度映射 (Shuttle 值 -> 滾動間隔秒數)
# 1=慢速, 7=極速
SPEED_MAP = {
    1: 0.2,
    2: 0.1,
    3: 0.08,
    4: 0.05,
    5: 0.03,
    6: 0.01,
    7: 0.005
}

# ================= 核心邏輯區 =================

mouse = MouseController()
keyboard = KeyboardController()
current_app = "default"

# 狀態變數
last_shuttle_val = 0
shuttle_active = False
next_scroll_time = 0

last_jog_val = None # 初始值設為 None，第一次讀取時校正

def get_active_app():
    """獲取當前 App 名稱"""
    try:
        app = NSWorkspace.sharedWorkspace().activeApplication()
        return app['NSApplicationName']
    except:
        return "default"

def to_signed(n):
    """將 0-255 轉為 -128 到 127"""
    return n - 256 if n > 127 else n

def perform_scroll(direction, multiplier):
    """執行滾動 (direction > 0 向下)"""
    # macOS 的 scroll 負值通常是向下 (視系統設定而定，若相反請把 -1 改 1)
    dy = -1 if direction > 0 else 1
    mouse.scroll(0, dy * multiplier)

def perform_key(key_def):
    """執行按鍵組合"""
    if isinstance(key_def, str):
        # 單一字元 (如 'j', 'l')
        keyboard.press(key_def)
        keyboard.release(key_def)
    elif isinstance(key_def, dict):
        # 組合鍵 (如 Ctrl+Tab)
        modifiers = key_def.get("modifiers", [])
        key = key_def.get("key")

        # 按下所有修飾鍵
        for mod in modifiers: keyboard.press(mod)

        # 按下主鍵
        keyboard.press(key)
        keyboard.release(key)

        # 放開所有修飾鍵
        for mod in reversed(modifiers): keyboard.release(mod)

def handle_shuttle(value):
    global shuttle_active, next_scroll_time, last_shuttle_val

    # 轉換成有號整數 (-7 ~ +7)
    s_val = to_signed(value)
    last_shuttle_val = s_val

    if s_val == 0:
        shuttle_active = False
        return

    # 讀取設定
    config = APP_CONFIG.get(current_app, APP_CONFIG["default"])
    mode = config.get("shuttle_mode", "scroll")

    # 滾動模式
    if mode == "scroll":
        shuttle_active = True
        abs_val = abs(s_val)
        interval = SPEED_MAP.get(abs_val, 0.1)

        if time.time() >= next_scroll_time:
            multiplier = config.get("scroll_speed", 1)
            # 傳入 s_val 決定方向
            perform_scroll(s_val, multiplier)
            next_scroll_time = time.time() + interval

    # 按鍵模式 (適合影片剪輯 J/L)
    elif mode == "key":
        shuttle_active = True
        key = config.get("key_right") if s_val > 0 else config.get("key_left")

        # 簡單頻率控制 (0.2秒觸發一次，避免送出太多按鍵)
        if time.time() >= next_scroll_time:
            if key: perform_key(key)
            next_scroll_time = time.time() + 0.2

def handle_jog(current_val):
    global last_jog_val

    # 第一次執行時，先記錄當前位置，不動作
    if last_jog_val is None:
        last_jog_val = current_val
        return

    # 計算差值 (Delta)
    diff = current_val - last_jog_val

    # 處理 0-255 的邊界跨越 (Wrap-around)
    # 例如從 255 變成 0 (diff = -255)，其實是 +1
    if diff > 127:
        diff -= 256
    elif diff < -127:
        diff += 256

    last_jog_val = current_val

    # 如果沒變動就忽略
    if diff == 0: return

    # 判斷方向
    direction = 1 if diff > 0 else -1 # 1=右轉, -1=左轉

    # 讀取設定
    config = APP_CONFIG.get(current_app, APP_CONFIG["default"])
    mode = config.get("jog_mode", "key")

    # 為了處理快速轉動，我們可以用 diff 的大小來重複執行
    # 這裡簡化為：有轉動就觸發一次
    steps = abs(diff)

    for _ in range(steps):
        if mode == "scroll":
            multiplier = config.get("jog_scroll_multiplier", 5)
            perform_scroll(direction, multiplier)

        elif mode == "key":
            key_def = config.get("jog_right") if direction > 0 else config.get("jog_left")
            if key_def: perform_key(key_def)

def main():
    global current_app, shuttle_active, last_shuttle_val
    print("正在連接 ShuttlePro v2 ...")

    try:
        h = hid.device()
        h.open(VID, PID)
        h.set_nonblocking(1)
        print("✅ 裝置已啟動！")
        print("💡 提示：請確保 Terminal 已獲得「輸入監控」權限。")

        app_check_timer = 0

        while True:
            # 1. 讀取 USB 資料
            data = h.read(64)
            if data:
                # 處理 Shuttle (Byte 0)
                if len(data) > SHUTTLE_INDEX:
                    handle_shuttle(data[SHUTTLE_INDEX])

                # 處理 Jog (Byte 1)
                if len(data) > JOG_INDEX:
                    handle_jog(data[JOG_INDEX])

            # 2. 持續執行 Shuttle 的連發 (如果轉盤沒歸零)
            if shuttle_active and last_shuttle_val != 0:
                handle_shuttle(last_shuttle_val)

            # 3. 檢查前景軟體 (每 0.5 秒檢查一次)
            if time.time() - app_check_timer > 0.5:
                new_app = get_active_app()
                if new_app != current_app:
                    print(f"🔄 切換設定檔: {new_app}")
                    current_app = new_app
                    # 切換軟體時重置狀態，避免誤觸
                    shuttle_active = False
                app_check_timer = time.time()

            # 極短暫休眠，避免 CPU 飆高
            time.sleep(0.005)

    except IOError as e:
        print(f"❌ 無法開啟裝置: {e}")
    except KeyboardInterrupt:
        print("\n👋 程式結束")
    finally:
        try:
            h.close()
        except:
            pass

if __name__ == "__main__":
    main()
