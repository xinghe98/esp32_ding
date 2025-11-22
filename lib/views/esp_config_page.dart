import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/esp_device_controller.dart';
import '../widgets/connection_status_dot.dart';
import 'scan_view.dart';
import 'config_form_view.dart';

class EspConfigPage extends StatefulWidget {
  const EspConfigPage({super.key});

  @override
  State<EspConfigPage> createState() => _EspConfigPageState();
}

class _EspConfigPageState extends State<EspConfigPage> {
  final EspDeviceController _controller = EspDeviceController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("网点配置更换"),
                const SizedBox(width: 8),
                ConnectionStatusDot(connected: _controller.writeChar != null),
              ],
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.terminal_rounded),
                onPressed: () => _showLogs(context),
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainer,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: _controller.writeChar != null
                          ? ConfigFormView(controller: _controller)
                          : ScanView(controller: _controller),
                    ),
                  ),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        "powered by xinghe98",
        style: GoogleFonts.outfit(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  void _showLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("运行日志", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _controller.logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _controller.logs[index],
                      style: GoogleFonts.firaCode(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
