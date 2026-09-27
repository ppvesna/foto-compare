import 'package:flutter/material.dart';

class AppTheme {
  // Общая нейтральная палитра: светлые холодные фоны,
  // графитовые рабочие панели и один бирюзовый акцент.
  static const Color blue = Color(0xFF2B9DA6);
  static const Color blueDark = Color(0xFF35434A);
  static const Color blueLight = Color(0xFF9DD8DC);
  static const Color appBackground = Color(0xFFE7ECEF);
  static const Color surface = Color(0xFFF7F9FA);
  static const Color surfaceMuted = Color(0xFFEDF1F3);
  static const Color workspaceChrome = Color(0xFFDCEBED);
  static const Color workspaceChromeLine = Color(0xFF85B7BC);
  static const Color graphite = Color(0xFF354047);
  static const Color graphiteSoft = Color(0xFF46545B);
  static const Color canvas = Color(0xFF3B454A);
  static const Color line = Color(0xFFCDD6DA);
  static const Color silver = surfaceMuted;
  static const Color silverDark = Color(0xFFAAB6BC);
  static const Color silverLight = surface;
  static const Color border = line;
  static const Color green = Color(0xFF3A6E37);
  static const Color simHigh = Color(0xFF3A8C2F);
  static const Color simMid = Color(0xFFC8A020);
  static const Color simLow = Color(0xFFC82020);

  // Градиенты
  static const LinearGradient blueGrad = LinearGradient(
    colors: [Color(0xFFBCE4E5), Color(0xFF55B4BA), Color(0xFF2B9DA6)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient btnGrad = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF1F4F5), Color(0xFFDDE4E7)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient silverGrad = LinearGradient(
    colors: [Color(0xFFF9FAFB), Color(0xFFEDF1F3), Color(0xFFDDE4E7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Тени
  static const List<BoxShadow> shadowRaised = [
    BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(2, 2)),
    BoxShadow(color: Color(0x30FFFFFF), blurRadius: 2, offset: Offset(-1, -1)),
  ];
  static const List<BoxShadow> shadowSubtle = [
    BoxShadow(color: Color(0x25000000), blurRadius: 3, offset: Offset(1, 2)),
  ];

  static Color simColor(double pct) {
    if (pct >= 90) return simHigh;
    if (pct >= 65) return simMid;
    return simLow;
  }

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      surface: surface,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: appBackground,
      canvasColor: surface,
      dividerColor: line,
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
    );
  }
}
