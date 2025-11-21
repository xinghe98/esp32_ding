import bluetooth
import time
import json
import machine
import ubinascii
from machine import Pin, base_mac_addr

# =======================================================
# 1. 配置与存储管理
# =======================================================
CONFIG_FILE = 'ble_config.json'

# 默认配置 (你原本的硬编码值)
DEFAULT_CONFIG = {
    "mac": "7C:88:99:94:E8:62",
    "adv_hex": "02010617FF0001B5000223AAE2C3000001AAAA20761B011000000003033CFE"
}

def load_config():
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except:
        return DEFAULT_CONFIG

def save_config(mac_str, adv_hex_str):
    with open(CONFIG_FILE, 'w') as f:
        json.dump({"mac": mac_str, "adv_hex": adv_hex_str}, f)

# 加载配置
config = load_config()
CURRENT_MAC_STR = config['mac']
CURRENT_ADV_HEX = config['adv_hex']

# =======================================================
# 2. 硬件初始化 (LED)
# =======================================================
RIGHT_LED_PIN = 8
LEFT_LED_PIN = 8
right_led = Pin(RIGHT_LED_PIN, Pin.OUT)
left_led = Pin(LEFT_LED_PIN, Pin.OUT)
right_led.off()
left_led.off()

# =======================================================
# 3. MAC 地址处理 (保留你的逻辑)
# =======================================================
def apply_custom_mac(mac_str):
    # 将 "AA:BB:..." 转换为 bytearray
    mac_bytes = bytearray(ubinascii.unhexlify(mac_str.replace(':', '')))
    
    # 你的原始逻辑: base MAC = target MAC - 2
    mac_bytes[5] = mac_bytes[5] - 2
    
    print(f"Setting Base MAC to: {ubinascii.hexlify(mac_bytes)}")
    base_mac_addr(mac_bytes)

# 在激活蓝牙前应用 MAC
apply_custom_mac(CURRENT_MAC_STR)

# =======================================================
# 4. 蓝牙逻辑 (GATT Server + Broadcaster)
# =======================================================
ble = bluetooth.BLE()
ble.active(True)
# 配置 MTU 为 512 字节，以支持长数据包 (如 JSON 配置)
try:
    ble.config(mtu=512)
    print("MTU 配置为 512")
except Exception as e:
    print("MTU 配置失败:", e)

# 定义 UUID
# Service UUID (用于 Flutter 扫描识别)
SERVICE_UUID = bluetooth.UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
# Characteristic UUID (用于写入配置)
CHAR_UUID = bluetooth.UUID("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

# 全局接收缓冲区
_rx_buffer = bytearray()

# 蓝牙事件处理
def ble_irq(event, data):
    global _rx_buffer
    if event == 1: # _IRQ_CENTRAL_CONNECT
        conn_handle, _, _ = data
        print("设备已连接", conn_handle)
    
    elif event == 2: # _IRQ_CENTRAL_DISCONNECT
        conn_handle, _, _ = data
        print("设备已断开", conn_handle)
        _rx_buffer = bytearray() # 断开连接时清空缓冲区
        start_advertising()
        
    elif event == 3: # _IRQ_GATT_WRITE
        conn_handle, value_handle = data
        # 读取写入的数据
        buffer = ble.gatts_read(value_handle)
        _rx_buffer += buffer # 追加到缓冲区
        
        try:
            # 尝试解析 JSON
            data_str = _rx_buffer.decode('utf-8').strip()
            print("当前缓冲区:", data_str)
            
            # 简单的结束符检查，防止不完整的 JSON 导致报错
            if data_str.endswith('}'):
                new_settings = json.loads(data_str)
                print("完整 JSON 解析成功!")
                
                # 清空缓冲区
                _rx_buffer = bytearray()
                
                # 保存配置
                save_config(new_settings['mac'], new_settings['adv_hex'])
                
                print("配置已保存，即将重启...")
                
                # 关键：增加延时，确保蓝牙 Write Response 能成功发送回手机
                time.sleep(1.0)
                
                for _ in range(5):
                    right_led.on()
                    time.sleep(0.05)
                    right_led.off()
                    time.sleep(0.05)
                
                machine.reset()
            else:
                print("等待更多数据...")
            
        except Exception as e:
            print("解析未完成或错误:", e)
            # 解析失败说明数据可能还不完整，继续等待后续包
            pass

ble.irq(ble_irq)

# 注册服务
# ((Char_UUID, FLAGS),)  FLAGS: 8=WRITE, 2=READ
services = (
    (SERVICE_UUID, ((CHAR_UUID, bluetooth.FLAG_WRITE | bluetooth.FLAG_WRITE_NO_RESPONSE),)),
)
((char_handle,),) = ble.gatts_register_services(services)

# 准备广播数据
def start_advertising():
    # 1. 原始广播包 (用户自定义的 HEX)
    try:
        payload = ubinascii.unhexlify(CURRENT_ADV_HEX)
    except:
        print("Hex 格式错误，使用默认")
        payload = ubinascii.unhexlify(DEFAULT_CONFIG['adv_hex'])

    # 2. 扫描响应包 (设备名称)
    # 注意：为了让 Flutter 容易连上，建议在广播包或响应包里包含 Service UUID，
    # 但为了不破坏你的 raw payload，我们将 Service UUID 放在扫描响应里，或者仅靠名称扫描。
    # 这里保留你的名称逻辑，但建议加入 Service UUID 以便过滤。
    DEVICE_NAME = "ESP32-Config"
    name_bytes = DEVICE_NAME.encode('utf-8')
    
    # 构建扫描响应: [Len][Type 0x09 Name][Name] + [Len][Type 0x07 Complete UUID][UUID]
    # 简化版：只放名字，Flutter 通过名字过滤
    resp_payload = bytes([len(name_bytes) + 1, 0x09]) + name_bytes
    
    print(f"开始广播: MAC={CURRENT_MAC_STR}")
    # 间隔 100ms
    ble.gap_advertise(100000, adv_data=payload, resp_data=resp_payload)

# =======================================================
# 5. 主程序逻辑
# =======================================================
try:
    start_advertising()
    
    # --- 启动信号：左右LED快闪3次 ---
    print("启动信号：LED快闪...")
    for _ in range(3):
        right_led.on(); left_led.on()
        time.sleep(0.1)
        right_led.off(); left_led.off()
        time.sleep(0.1)

    # --- 主循环：心跳 ---
    print("进入主循环...")
    while True:
        left_led.on()
        time.sleep(2)
        left_led.off()
        time.sleep(1)

except KeyboardInterrupt:
    ble.active(False)
    right_led.off()
    left_led.off()
    print("程序已停止")
