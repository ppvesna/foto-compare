import 'package:flutter/material.dart';

class AppTheme {
  // Основная палитра: тёплый светло-синий вместо тяжёлого тёмно-фиолетового.
  static const Color blue = Color(0xFF2FA7E6);
  static const Color blueDark = Color(0xFF238FC8);
  static const Color blueLight = Color(0xFF9EDBFF);
  static const Color silver = Color(0xFFECE9D8);
  static const Color silverDark = Color(0xFFACA899);
  static const Color silverLight = Color(0xFFFFFFFE);
  static const Color border = Color(0xFF808080);
  static const Color green = Color(0xFF3A6E37);
  static const Color simHigh = Color(0xFF3A8C2F);
  static const Color simMid = Color(0xFFC8A020);
  static const Color simLow = Color(0xFFC82020);

  // Градиенты
  static const LinearGradient blueGrad = LinearGradient(
    colors: [Color(0xFFBFEAFF), Color(0xFF4FB8F0), Color(0xFF2F9DD8)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient btnGrad = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFECE9D8), Color(0xFFC8C4BC)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient silverGrad = LinearGradient(
    colors: [Color(0xFFF5F3EC), Color(0xFFECE9D8), Color(0xFFD8D4C8)],
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

  static ThemeData get theme => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: silver,
        useMaterial3: true,
      );
}
