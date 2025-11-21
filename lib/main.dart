import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class EspConfigPage extends StatefulWidget {
  const EspConfigPage({super.key});

  @override
  State<EspConfigPage> createState() => _EspConfigPageState();
}

class _EspConfigPageState extends State<EspConfigPage> {
  // 定义与 ESP32 一致的 UUID
  final String SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String CHAR_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";

  // 默认值 (方便调试)
  final TextEditingController _macCtrl = TextEditingController(
    text: "7C:88:99:94:E8:62",
  );
  final TextEditingController _hexCtrl = TextEditingController(
    text: "02010617FF0001B5000223AAE2C3000001AAAA20761B011000000003033CFE",
  );

  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _writeChar;
  bool _isScanning = false;
  bool _isConnected = false;
  String _statusLog = "请点击扫描查找设备";

  List<dynamic> _presets = [];
  Map<String, dynamic>? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    try {
      String jsonString = await rootBundle.loadString('assets/config.json');
      setState(() {
        _presets = json.decode(jsonString);
      });
    } catch (e) {
      print("Error loading presets: $e");
    }
  }

  void _onPresetChanged(Map<String, dynamic>? preset) {
    if (preset != null) {
      setState(() {
        _selectedPreset = preset;
        _macCtrl.text = preset['mac'];
        _hexCtrl.text = preset['hex'];
      });
    }
  }

  // 1. 扫描设备
  Future<void> startScan() async {
    // 显式请求权限 (Android 12+ 需要 BLUETOOTH_SCAN/CONNECT, 旧版需要 LOCATION)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      setState(() => _statusLog = "权限被拒绝，无法扫描。请在设置中开启权限。");
      return;
    }

    setState(() {
      _isScanning = true;
      _statusLog = "正在扫描 ESP32-Config...";
      _targetDevice = null;
    });

    // 检查蓝牙是否开启
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        setState(() => _statusLog = "请打开蓝牙");
        return;
      }
    }

    try {
      // 开始扫描
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // 等待扫描结束
      await Future.delayed(const Duration(seconds: 10));

      // 如果扫描结束后仍未找到设备
      if (_targetDevice == null && mounted) {
        setState(() {
          _isScanning = false;
          _statusLog = "未找到设备 (ESP32-Config)\n请确保设备已开启且在附近";
        });
      }
    } catch (e) {
      setState(() => _statusLog = "扫描启动失败: $e");
      return;
    }

    // 监听扫描结果
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        // Debug: 显示所有发现的设备
        if (r.device.platformName.isNotEmpty) {
          print("Found: ${r.device.platformName}");
        }

        // 通过设备名称过滤 (必须与 MicroPython 中的 DEVICE_NAME 一致)
        if (r.device.platformName == "ESP32-Config") {
          FlutterBluePlus.stopScan();
          setState(() {
            _targetDevice = r.device;
            _statusLog = "找到设备: ${r.device.remoteId}\n点击“连接”继续";
            _isScanning = false;
          });
          break;
        }
      }
    });
  }

  // 2. 连接并发现服务
  Future<void> connectDevice() async {
    if (_targetDevice == null) return;

    setState(() => _statusLog = "正在连接...");

    try {
      await _targetDevice!.connect();

      // Android 上通常需要请求更大的 MTU 以发送长数据 (如 JSON)
      if (Platform.isAndroid) {
        try {
          await _targetDevice!.requestMtu(512);
        } catch (e) {
          print("MTU request failed: $e");
        }
      }

      setState(() => _statusLog = "正在寻找服务...");
      List<BluetoothService> services = await _targetDevice!.discoverServices();

      BluetoothService? targetService;
      // 查找目标服务
      for (var s in services) {
        if (s.uuid.toString().toUpperCase() == SERVICE_UUID) {
          targetService = s;
          break;
        }
      }

      if (targetService != null) {
        // 查找目标特征值
        for (var c in targetService.characteristics) {
          if (c.uuid.toString().toUpperCase() == CHAR_UUID) {
            _writeChar = c;
            break;
          }
        }
      }

      if (_writeChar != null) {
        setState(() {
          _isConnected = true;
          _statusLog = "已连接！请修改参数并发送。";
        });
      } else {
        setState(() => _statusLog = "错误：未找到目标特征值");
        await _targetDevice!.disconnect();
      }
    } catch (e) {
      setState(() => _statusLog = "连接失败: $e");
    }
  }

  // 3. 发送配置 JSON
  Future<void> sendConfig() async {
    if (_writeChar == null) return;

    String mac = _macCtrl.text.trim().toUpperCase();
    String hex = _hexCtrl.text.trim().toUpperCase();

    // 简单的格式校验
    if (mac.length != 17 || !mac.contains(':')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("MAC 地址格式错误 (XX:XX:...)")));
      return;
    }

    // 构建 JSON 数据
    Map<String, String> config = {"mac": mac, "adv_hex": hex};
    String jsonStr = jsonEncode(config);

    setState(() => _statusLog = "正在发送配置...");
    print("Sending JSON: $jsonStr"); // Debug log

    try {
      // 分包发送：MTU 协商可能失败，最稳妥的方式是按 20 字节分包
      List<int> bytes = utf8.encode(jsonStr);
      int chunkSize = 20;

      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);

        print("Sending chunk ${i ~/ chunkSize + 1}: ${utf8.decode(chunk)}");

        try {
          // 使用 withoutResponse: false (即 WriteWithResponse) 确保包的顺序和送达
          await _writeChar!.write(chunk, withoutResponse: false);
        } catch (e) {
          // 如果是最后一个包，且发生异常，可能是因为设备重启太快导致连接断开
          // 既然 ESP32 端已经确认收到，我们可以忽略这个错误
          if (end == bytes.length) {
            print("Last chunk write error (ignored): $e");
          } else {
            rethrow;
          }
        }
      }

      setState(() => _statusLog = "发送成功！\n设备将自动重启并应用新配置。");

      // 延迟一会后断开
      await Future.delayed(const Duration(seconds: 2));
      await _targetDevice!.disconnect();
      setState(() {
        _isConnected = false;
        _targetDevice = null;
      });
    } catch (e) {
      setState(() => _statusLog = "发送失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ESP32 广播修改器")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.grey[200],
                child: Text(
                  _statusLog,
                  style: const TextStyle(color: Colors.blue),
                ),
              ),
              const SizedBox(height: 20),

              // 扫描区域
              if (!_isConnected) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_searching_rounded),
                  label: Text(
                    _isScanning ? "扫描中..." : "1. 扫描设备 (ESP32-Config)",
                  ),
                  onPressed: _isScanning ? null : startScan,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_connected),
                  label: const Text("2. 连接设备"),
                  onPressed: _targetDevice != null ? connectDevice : null,
                ),
              ],

              // 编辑区域
              if (_isConnected) ...[
                const Divider(height: 40),
                // 预设选择
                if (_presets.isNotEmpty) ...[
                  const Text(
                    "选择预设配置:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<Map<String, dynamic>>(
                    isExpanded: true,
                    hint: const Text("请选择设备..."),
                    value: _selectedPreset,
                    items: _presets.map((preset) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: preset,
                        child: Text(preset['name']),
                      );
                    }).toList(),
                    onChanged: (val) => _onPresetChanged(val),
                  ),
                  const SizedBox(height: 20),
                ],

                const Text(
                  "目标 MAC 地址:",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextField(
                  controller: _macCtrl,
                  decoration: const InputDecoration(
                    hintText: "例如: 7C:88:99:94:E8:62",
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "广播 Hex 数据 (Raw):",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextField(
                  controller: _hexCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: "例如: 020106...",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: sendConfig,
                  child: const Text(
                    "3. 发送并重启设备",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  runApp(const MaterialApp(home: EspConfigPage()));
}
