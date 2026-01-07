import hid
import time

VID = 0x0b33
PID = 0x0030

def to_signed(n):
    """將 0-255 轉為 -128 到 127"""
    return n - 256 if n > 127 else n

try:
    h = hid.device()
    h.open(VID, PID)
    h.set_nonblocking(1)

    print(f"✅ 已連接: {h.get_product_string()}")
    print("=" * 60)
    print("請依照以下指令操作，觀察數值變化：")
    print("1. 將外圈 (Shuttle) 慢慢往右轉到底")
    print("2. 將外圈 (Shuttle) 慢慢往左轉到底")
    print("3. 轉動內圈 (Jog)")
    print("4. 按下任意按鍵")
    print("=" * 60)
    print(f"{'RAW (Hex)':<30} | {'Byte 0 (Signed)':<15} | {'Byte 1 (Signed)':<15}")
    print("-" * 60)

    last_data = None

    while True:
        data = h.read(64)
        if data:
            # 只有當數據改變時才顯示 (忽略重複訊號)
            if data != last_data:
                # 轉成 Hex 字串供參考
                hex_str = " ".join([f"{x:02x}" for x in data[:5]])

                # 將前兩個 Byte 轉成有號整數 (-1, -5, +5...)
                b0_signed = to_signed(data[0])
                b1_signed = to_signed(data[1])

                print(f"[{hex_str:<20}]   |   Val: {b0_signed:<10} |   Val: {b1_signed:<10}")

                last_data = data

        time.sleep(0.01)

except IOError:
    print("❌ 找不到裝置，請確認 USB 連接或是否有其他程式佔用。")
except KeyboardInterrupt:
    print("\n程式結束")
finally:
    try:
        h.close()
    except:
        pass
