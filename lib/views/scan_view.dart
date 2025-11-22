import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/esp_device_controller.dart';

class ScanView extends StatelessWidget {
  final EspDeviceController controller;
  const ScanView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon / Illustration
          Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bluetooth_searching_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
              .animate(
                onPlay: (c) => controller.isScanning ? c.repeat() : c.stop(),
              )
              .shimmer(duration: 2.seconds, color: Colors.white54),

          const SizedBox(height: 48),

          Text(
            controller.isScanning ? "正在搜索设备..." : "准备连接",
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            "请确保您的 ESP32 设备已开启\n并处于广播模式",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 48),

          if (controller.isConnecting)
            const CircularProgressIndicator()
          else
            FilledButton.icon(
              onPressed: controller.isScanning
                  ? null
                  : () {
                      controller.startScan(
                        onTimeout: () {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text("⚠️ 未找到设备，请确保设备已开启"),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          }
                        },
                      );
                    },
              icon: const Icon(Icons.radar_rounded),
              label: const Text("扫描并连接"),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ).animate().scale(delay: 200.ms, curve: Curves.elasticOut),
        ],
      ),
    );
  }
}
