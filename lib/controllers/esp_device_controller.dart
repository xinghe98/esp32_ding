import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class EspDeviceController extends ChangeNotifier {
  // BLE UUID 定义
  final String SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String CHAR_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";

  // 设备状态
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? writeChar;
  bool isScanning = false;
  bool isConnecting = false;
  bool isSending = false;

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  List<dynamic> presets = [];

  EspDeviceController() {
    _loadPresets();
  }

  void log(String message) {
    final time = DateTime.now().toString().substring(11, 19);
    _logs.insert(0, "[$time] $message");
    notifyListeners();
  }

  Future<void> _loadPresets() async {
    try {
      String jsonString = await rootBundle.loadString('assets/config.json');
      presets = json.decode(jsonString);
      notifyListeners();
    } catch (e) {
      log("Error loading presets: $e");
    }
  }

  Future<bool> checkPermissions() async {
    List<Permission> permissions = [];

    if (Platform.isAndroid) {
      // Android 12+ 需要特定权限
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]);

      // Android 10-11 兼容 (使用定位权限)

      try {
        final locationStatus = await Permission.location.status;
        if (locationStatus.isDenied) {
          permissions.add(Permission.location);
        }
      } catch (e) {
        permissions.add(Permission.location);
      }
    } else if (Platform.isIOS) {
      permissions.add(Permission.bluetooth);
    }

    Map<Permission, PermissionStatus> statuses = await permissions.request();

    bool hasPermission = true;
    if (Platform.isAndroid) {
      hasPermission =
          (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
          (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
    } else if (Platform.isIOS) {
      hasPermission = statuses[Permission.bluetooth]?.isGranted ?? false;
    }

    if (!hasPermission) {
      log("❌ 权限被拒绝，请在设置中开启蓝牙权限");
      return false;
    }
    return true;
  }

  Future<void> startScan({VoidCallback? onTimeout}) async {
    if (!await checkPermissions()) return;

    // 确保蓝牙已开启
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          log("⚠️ 无法自动开启蓝牙。");
          return;
        }
      } else {
        log("⚠️ 蓝牙未开启，请在设置中开启。");
        return;
      }
    }

    isScanning = true;
    targetDevice = null;
    log("🔍 开始扫描 ESP32-Config...");
    notifyListeners();

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // 监听扫描结果
      var subscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == "ESP32-Config") {
            _foundDevice(r.device);
            break;
          }
        }
      });

      // 超时停止扫描

      await Future.delayed(const Duration(seconds: 10));
      if (isScanning) {
        await FlutterBluePlus.stopScan();
        subscription.cancel();
        isScanning = false;
        if (targetDevice == null) {
          log("⚠️ 未找到设备。请确保设备已开启。");
          if (onTimeout != null) onTimeout();
        }
        notifyListeners();
      }
    } catch (e) {
      log("❌ 扫描错误: $e");
      isScanning = false;
      notifyListeners();
    }
  }

  void _foundDevice(BluetoothDevice device) {
    FlutterBluePlus.stopScan();
    targetDevice = device;
    isScanning = false;
    log("✅ 找到设备: ${device.remoteId}");
    notifyListeners();

    // 自动连接以提升体验
    connectDevice();
  }

  Future<void> connectDevice() async {
    if (targetDevice == null) return;

    isConnecting = true;
    log("🔗 正在连接...");
    notifyListeners();

    try {
      await targetDevice!.connect();

      // if (Platform.isAndroid) {
      //   try {
      //     await targetDevice!.requestMtu(512);
      //   } catch (e) {
      //     // Ignore MTU error
      //   }
      // }

      log("📂 正在发现服务...");
      List<BluetoothService> services = await targetDevice!.discoverServices();

      BluetoothService? targetService;
      for (var s in services) {
        if (s.uuid.toString().toUpperCase() == SERVICE_UUID) {
          targetService = s;
          break;
        }
      }

      if (targetService != null) {
        for (var c in targetService.characteristics) {
          if (c.uuid.toString().toUpperCase() == CHAR_UUID) {
            writeChar = c;
            break;
          }
        }
      }

      if (writeChar != null) {
        log("🚀 已连接！准备配置。");
      } else {
        log("❌ 错误：未找到目标特征值");
        await disconnect();
      }
    } catch (e) {
      log("❌ 连接失败: $e");
      await disconnect();
    } finally {
      isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      if (targetDevice != null) {
        await targetDevice!.disconnect();
      }
    } catch (e) {
      log("⚠️ 断开连接时出错: $e");
    } finally {
      targetDevice = null;
      writeChar = null;
      log("🔌 已断开连接");
      notifyListeners();
    }
  }

  Future<void> sendConfig(
    String mac,
    String hex, {
    VoidCallback? onSuccess,
  }) async {
    if (writeChar == null) return;

    isSending = true;
    notifyListeners();

    String cleanMac = mac.trim().toUpperCase();
    String cleanHex = hex.trim().toUpperCase();

    Map<String, String> config = {"mac": cleanMac, "adv_hex": cleanHex};
    String jsonStr = jsonEncode(config);

    log("📤 发送配置...");

    try {
      List<int> bytes = utf8.encode(jsonStr);
      int chunkSize = 20;

      // 检查是否支持无响应写入以提高速度
      bool withoutResponse = false;
      if (writeChar!.properties.writeWithoutResponse) {
        withoutResponse = true;
      }

      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);
        await writeChar!.write(chunk, withoutResponse: withoutResponse);
        // Add small delay to prevent congestion
        if (withoutResponse) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      log("✨ 配置成功！设备正在重启...");
      if (onSuccess != null) onSuccess();
      await Future.delayed(const Duration(seconds: 2));
      await disconnect();
    } catch (e) {
      log("❌ 发送失败: $e");
    } finally {
      isSending = false;
      notifyListeners();
    }
  }
}
