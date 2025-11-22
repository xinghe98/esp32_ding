import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/esp_device_controller.dart';

class ConfigFormView extends StatefulWidget {
  final EspDeviceController controller;
  const ConfigFormView({super.key, required this.controller});

  @override
  State<ConfigFormView> createState() => _ConfigFormViewState();
}

class _ConfigFormViewState extends State<ConfigFormView> {
  final TextEditingController _macCtrl = TextEditingController(
    text: "7C:88:99:94:E8:62",
  );
  final TextEditingController _hexCtrl = TextEditingController(
    text: "02010617FF0001B5000223AAE2C3000001AAAA20761B011000000003033CFE",
  );
  Map<String, dynamic>? _selectedPreset;

  @override
  void initState() {
    super.initState();
    if (widget.controller.presets.isNotEmpty) {
      _onPresetChanged(widget.controller.presets.first);
    }
  }

  void _onPresetChanged(dynamic preset) {
    if (preset != null) {
      setState(() {
        _selectedPreset = preset;
        _macCtrl.text = preset['mac'];
        _hexCtrl.text = preset['hex'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "已连接设备",
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        () {
                          final deviceId = widget
                              .controller
                              .targetDevice
                              ?.remoteId
                              .toString()
                              .toUpperCase();
                          if (deviceId == null) return "Unknown";
                          final preset = widget.controller.presets.firstWhere(
                            (p) =>
                                p['mac'].toString().toUpperCase() == deviceId,
                            orElse: () => null,
                          );
                          return preset != null
                              ? "当前使用的网点为：${preset['name']}"
                              : "当前使用的网点为：$deviceId";
                        }(),
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: widget.controller.disconnect,
                  tooltip: "断开连接",
                ),
              ],
            ),
          ).animate().slideY(begin: -0.2, end: 0),

          const SizedBox(height: 32),

          // Preset Selector
          if (widget.controller.presets.isNotEmpty)
            DropdownButtonFormField<dynamic>(
              decoration: const InputDecoration(
                labelText: "修改网点",
                prefixIcon: Icon(Icons.bookmarks_rounded),
              ),
              value: _selectedPreset,
              items: widget.controller.presets.map((preset) {
                return DropdownMenuItem<dynamic>(
                  value: preset,
                  child: Text(preset['name']),
                );
              }).toList(),
              onChanged: _onPresetChanged,
            ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 24),

          // // Form Fields
          // TextField(
          //   controller: _macCtrl,
          //   decoration: const InputDecoration(
          //     labelText: "MAC 地址",
          //     hintText: "XX:XX:XX:XX:XX:XX",
          //     prefixIcon: Icon(Icons.fingerprint_rounded),
          //     helperText: "目标设备的物理地址",
          //   ),
          //   style: GoogleFonts.firaCode(),
          // ).animate().fadeIn(delay: 200.ms),

          // const SizedBox(height: 24),

          // TextField(
          //   controller: _hexCtrl,
          //   maxLines: 3,
          //   decoration: const InputDecoration(
          //     labelText: "广播数据 (Hex)",
          //     hintText: "020106...",
          //     prefixIcon: Icon(Icons.data_object_rounded),
          //     helperText: "十六进制广播载荷",
          //   ),
          //   style: GoogleFonts.firaCode(fontSize: 13),
          // ).animate().fadeIn(delay: 300.ms),
          // const SizedBox(height: 40),

          // Action Button
          FilledButton.icon(
            onPressed: widget.controller.isSending
                ? null
                : () {
                    widget.controller.sendConfig(
                      _macCtrl.text,
                      _hexCtrl.text,
                      onSuccess: () {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text("✨ 配置成功！设备正在重启..."),
                              backgroundColor: Colors.green.shade600,
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        }
                      },
                    );
                  },
            icon: widget.controller.isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(widget.controller.isSending ? "正在写入..." : "应用修改"),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }
}
