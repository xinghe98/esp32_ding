import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  runApp(const EspConfigApp());
}

class EspConfigApp extends StatelessWidget {
  const EspConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Config',
      debugShowCheckedModeBanner: false,
      theme: FlexThemeData.light(
        scheme: FlexScheme.mandyRed,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          blendOnColors: false,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        swapLegacyOnMaterial3: true,
        fontFamily: GoogleFonts.notoSans().fontFamily,
      ),
      darkTheme: FlexThemeData.dark(
        scheme: FlexScheme.mandyRed,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 13,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        swapLegacyOnMaterial3: true,
        fontFamily: GoogleFonts.notoSans().fontFamily,
      ),
      themeMode: ThemeMode.system,
      home: const EspConfigPage(),
    );
  }
}

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
  String _statusLog = "准备扫描";

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

  void _log(String message) {
    setState(() => _statusLog = message);
  }

  // 1. 扫描设备
  Future<void> startScan() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      _log("权限被拒绝。请在设置中开启蓝牙权限。");
      return;
    }

    setState(() {
      _isScanning = true;
      _statusLog = "正在扫描 ESP32-Config...";
      _targetDevice = null;
    });

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _log("请打开蓝牙");
        return;
      }
    }

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      await Future.delayed(const Duration(seconds: 10));

      if (_targetDevice == null && mounted) {
        setState(() {
          _isScanning = false;
          _statusLog = "未找到设备 (ESP32-Config)。请确保设备已开启。";
        });
      }
    } catch (e) {
      _log("扫描失败: $e");
      return;
    }

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == "ESP32-Config") {
          FlutterBluePlus.stopScan();
          setState(() {
            _targetDevice = r.device;
            _statusLog = "找到设备: ${r.device.remoteId}\n点击“连接”继续。";
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

    _log("正在连接...");

    try {
      await _targetDevice!.connect();

      if (Platform.isAndroid) {
        try {
          await _targetDevice!.requestMtu(512);
        } catch (e) {
          print("MTU request failed: $e");
        }
      }

      _log("正在发现服务...");
      List<BluetoothService> services = await _targetDevice!.discoverServices();

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
            _writeChar = c;
            break;
          }
        }
      }

      if (_writeChar != null) {
        setState(() {
          _isConnected = true;
          _statusLog = "已连接！准备配置。";
        });
      } else {
        _log("错误：未找到目标特征值");
        await _targetDevice!.disconnect();
      }
    } catch (e) {
      _log("连接失败: $e");
    }
  }

  // 3. 发送配置 JSON
  Future<void> sendConfig() async {
    if (_writeChar == null) return;

    String mac = _macCtrl.text.trim().toUpperCase();
    String hex = _hexCtrl.text.trim().toUpperCase();

    if (mac.length != 17 || !mac.contains(':')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("MAC 地址格式无效 (XX:XX:...)")));
      return;
    }

    Map<String, String> config = {"mac": mac, "adv_hex": hex};
    String jsonStr = jsonEncode(config);

    _log("正在发送配置...");
    print("Sending JSON: $jsonStr");

    try {
      List<int> bytes = utf8.encode(jsonStr);
      int chunkSize = 20;

      for (int i = 0; i < bytes.length; i += chunkSize) {
        int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        List<int> chunk = bytes.sublist(i, end);

        try {
          await _writeChar!.write(chunk, withoutResponse: false);
        } catch (e) {
          if (end == bytes.length) {
            print("Last chunk write error (ignored): $e");
          } else {
            rethrow;
          }
        }
      }

      _log("成功！设备正在重启...");

      await Future.delayed(const Duration(seconds: 2));
      await _targetDevice!.disconnect();
      setState(() {
        _isConnected = false;
        _targetDevice = null;
      });
    } catch (e) {
      _log("发送失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isTablet = constraints.maxWidth > 600;
          return Row(
            children: [
              if (isTablet)
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: _buildSidePanel(context),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text("ESP32 配置工具"),
                    centerTitle: !isTablet,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    titleTextStyle: GoogleFonts.outfit(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: isTablet
                        ? _buildMainContent(context)
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildStatusCard(context),
                                const SizedBox(height: 24),
                                _buildScanSection(context),
                                const SizedBox(height: 24),
                                if (_isConnected) ...[
                                  const Divider(),
                                  const SizedBox(height: 24),
                                  _buildConfigForm(context),
                                ],
                                const SizedBox(height: 40),
                                Center(
                                  child: Text(
                                    "power by xinghe98",
                                    style: GoogleFonts.outfit(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "设备状态",
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          _buildStatusCard(context),
          const Spacer(),
          _buildScanSection(context),
          const SizedBox(height: 24),
          Center(
            child: Text(
              "power by xinghe98",
              style: GoogleFonts.outfit(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    if (!_isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              "请连接设备以进行配置",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(child: _buildConfigForm(context));
  }

  Widget _buildStatusCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  "日志输出",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _statusLog,
              style: GoogleFonts.firaCode(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildScanSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isConnected) ...[
          FilledButton.icon(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(_isScanning ? "扫描中..." : "扫描设备"),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _isScanning ? null : startScan,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_rounded),
            label: const Text("连接设备"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _targetDevice != null ? connectDevice : null,
          ),
        ] else
          FilledButton.icon(
            icon: const Icon(Icons.link_off_rounded),
            label: const Text("断开连接"),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              await _targetDevice?.disconnect();
              setState(() {
                _isConnected = false;
                _targetDevice = null;
                _statusLog = "已断开连接";
              });
            },
          ),
      ],
    );
  }

  Widget _buildConfigForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "配置选项",
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        if (_presets.isNotEmpty) ...[
          DropdownButtonFormField<Map<String, dynamic>>(
            decoration: InputDecoration(
              labelText: "选择预设配置",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
            value: _selectedPreset,
            items: _presets.map((preset) {
              return DropdownMenuItem<Map<String, dynamic>>(
                value: preset,
                child: Text(preset['name']),
              );
            }).toList(),
            onChanged: _onPresetChanged,
          ),
          const SizedBox(height: 24),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.send_rounded),
            label: const Text("应用配置"),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: sendConfig,
          ),
        ),
      ],
    ).animate().fadeIn().slideX(begin: 0.1, end: 0);
  }
}
