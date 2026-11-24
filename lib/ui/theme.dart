import 'package:flutter/material.dart';

/// Farben passend zum Vintage-Kartenset (Creme, Gold, Dunkelblau, Rot).
class JassColors {
  static const felt = Color(0xFF1E4A3B);
  static const feltDark = Color(0xFF14352A);
  static const gold = Color(0xFFC9A25A);
  static const cream = Color(0xFFFBF6EA);
  static const navy = Color(0xFF1B2B38);
  static const red = Color(0xFFA8243A);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: JassColors.felt,
    brightness: Brightness.dark,
    primary: JassColors.gold,
    surface: JassColors.feltDark,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: JassColors.felt,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: JassColors.gold,
        foregroundColor: JassColors.navy,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      ),
    ),
  );
}
