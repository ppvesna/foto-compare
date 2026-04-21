import 'package:flutter/material.dart';

class AppTheme {
  // XP цвета
  static const Color blue      = Color(0xFF245EDC);
  static const Color blueDark  = Color(0xFF0A246A);
  static const Color silver    = Color(0xFFECE9D8);
  static const Color silverDark= Color(0xFFACA899);
  static const Color border    = Color(0xFF808080);
  static const Color green     = Color(0xFF3A6E37);
  static const Color simHigh   = Color(0xFF3A8C2F);
  static const Color simMid    = Color(0xFFC8A020);
  static const Color simLow    = Color(0xFFC82020);

  static const LinearGradient blueGrad = LinearGradient(
    colors: [Color(0xFF4A9BF5), Color(0xFF245EDC), Color(0xFF1A4DB8)],
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
  );
  static const LinearGradient btnGrad = LinearGradient(
    colors: [Color(0xFFFFF9F0), Color(0xFFECE9D8), Color(0xFFD4D0C8)],
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
  );

  static Color simColor(double pct) {
    if (pct >= 80) return simHigh;
    if (pct >= 70) return simMid;
    return simLow;
  }

  static ThemeData get theme => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: blue),
    scaffoldBackgroundColor: silver,
    fontFamily: 'Arial',
    useMaterial3: true,
  );
}
