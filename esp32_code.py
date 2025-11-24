import bluetooth
import time
import json
import machine
import ubinascii
from machine import Pin, base_mac_addr

CONFIG_FILE = 'ble_config.json'

# 如果配置文件丢失或损坏，使用默认配置
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

# 加载当前配置
config = load_config()
CURRENT_MAC_STR = config['mac']
CURRENT_ADV_HEX = config['adv_hex']

# 硬件初始化 (LED)
RIGHT_LED_PIN = 8
LEFT_LED_PIN = 8
right_led = Pin(RIGHT_LED_PIN, Pin.OUT)
left_led = Pin(LEFT_LED_PIN, Pin.OUT)
right_led.off()
left_led.off()

def apply_custom_mac(mac_str):
    # 将 MAC 字符串转换为字节
    mac_bytes = bytearray(ubinascii.unhexlify(mac_str.replace(':', '')))
    
    # 调整基础 MAC 地址 (根据硬件要求偏移 -2)
    mac_bytes[5] = mac_bytes[5] - 2
    
    print(f"设置基础 MAC 为: {ubinascii.hexlify(mac_bytes)}")
    base_mac_addr(mac_bytes)

apply_custom_mac(CURRENT_MAC_STR)

# 蓝牙设置
ble = bluetooth.BLE()
ble.active(True)

# 将 MTU 设置为 512 以支持大数据包 (例如 JSON 配置)
try:
    ble.config(mtu=512)
    print("MTU 已设置为 512")
except Exception as e:
    print("MTU 设置失败:", e)

# UUID 定义
SERVICE_UUID = bluetooth.UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
CHAR_UUID = bluetooth.UUID("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

_rx_buffer = bytearray()

def ble_irq(event, data):
    global _rx_buffer
    if event == 1: # _IRQ_CENTRAL_CONNECT
        conn_handle, _, _ = data
        print("设备已连接", conn_handle)
    
    elif event == 2: # _IRQ_CENTRAL_DISCONNECT
        conn_handle, _, _ = data
        print("设备已断开", conn_handle)
        _rx_buffer = bytearray()
        start_advertising()
        
    elif event == 3: # _IRQ_GATT_WRITE
        conn_handle, value_handle = data
        buffer = ble.gatts_read(value_handle)
        _rx_buffer += buffer
        
        try:
            data_str = _rx_buffer.decode('utf-8').strip()
            print("缓冲区:", data_str)
            
            # 简单的 JSON 完整性检查
            if data_str.endswith('}'):
                new_settings = json.loads(data_str)
                print("JSON 解析成功")
                
                _rx_buffer = bytearray()
                save_config(new_settings['mac'], new_settings['adv_hex'])
                
                print("配置已保存，正在重启...")
                
                # 延迟以确保响应在重启前发送
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
            print("解析错误或数据不完整:", e)
            pass

ble.irq(ble_irq)

# 注册服务
# FLAGS: 8=WRITE, 2=READ
services = (
    (SERVICE_UUID, ((CHAR_UUID, bluetooth.FLAG_WRITE | bluetooth.FLAG_WRITE_NO_RESPONSE),)),
)
((char_handle,),) = ble.gatts_register_services(services)

def start_advertising():
    try:
        payload = ubinascii.unhexlify(CURRENT_ADV_HEX)
    except:
        print("Hex 格式无效，使用默认值")
        payload = ubinascii.unhexlify(DEFAULT_CONFIG['adv_hex'])

    # 扫描响应 (设备名称)
    DEVICE_NAME = "ESP32-Config"
    name_bytes = DEVICE_NAME.encode('utf-8')
    
    # [Len][Type 0x09 Name][Name]
    resp_payload = bytes([len(name_bytes) + 1, 0x09]) + name_bytes
    
    print(f"开始广播: MAC={CURRENT_MAC_STR}")
    ble.gap_advertise(100000, adv_data=payload, resp_data=resp_payload)

try:
    start_advertising()
    
    # 启动信号
    print("启动信号...")
    for _ in range(3):
        right_led.on(); left_led.on()
        time.sleep(0.1)
        right_led.off(); left_led.off()
        time.sleep(0.1)

    print("主循环...")
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
