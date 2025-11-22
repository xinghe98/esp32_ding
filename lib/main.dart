import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'views/esp_config_page.dart';

void main() {
  runApp(const EspConfigApp());
}

// --- App Entry Point & Theme ---

class EspConfigApp extends StatelessWidget {
  const EspConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    const FlexScheme scheme = FlexScheme.deepBlue;

    return MaterialApp(
      title: '网点更换',
      debugShowCheckedModeBanner: false,
      theme: FlexThemeData.light(
        scheme: scheme,
        useMaterial3: true,
        fontFamily: GoogleFonts.outfit().fontFamily,
        subThemesData: const FlexSubThemesData(
          inputDecoratorBorderType: FlexInputBorderType.outline,
          inputDecoratorRadius: 12.0,
          fabUseShape: true,
          interactionEffects: true,
          bottomNavigationBarElevation: 0,
          navigationBarElevation: 0,
        ),
      ),
      darkTheme: FlexThemeData.dark(
        scheme: scheme,
        useMaterial3: true,
        fontFamily: GoogleFonts.outfit().fontFamily,
        subThemesData: const FlexSubThemesData(
          inputDecoratorBorderType: FlexInputBorderType.outline,
          inputDecoratorRadius: 12.0,
          fabUseShape: true,
          interactionEffects: true,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const EspConfigPage(),
    );
  }
}
