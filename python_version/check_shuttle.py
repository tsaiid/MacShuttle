# check_shuttle.py
import hid
import time

# ShuttlePro v2 常見 ID，若抓不到請改回你查到的
VID = 0x0b33
PID = 0x0030

try:
    h = hid.device()
    h.open(VID, PID)
    print(f"裝置已連接: {h.get_manufacturer_string()} {h.get_product_string()}")
    h.set_nonblocking(1)

    while True:
        data = h.read(64)
        if data:
            # 將數據轉為帶有索引的 Hex，方便你對照
            # 格式: [index: value]
            formatted = [f"{i}:{hex(x)}" for i, x in enumerate(data)]
            print(f"Data: {formatted}")
        time.sleep(0.01)

except Exception as e:
    print(f"錯誤: {e}")
