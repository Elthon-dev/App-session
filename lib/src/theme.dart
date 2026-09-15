import 'package:flutter/material.dart';

/// Nord palette (dark).
class Nord {
  Nord._();

  static const bg = Color(0xFF2E3440); // nord0
  static const surface = Color(0xFF3B4252); // nord1
  static const border = Color(0xFF434C5E); // nord2
  static const muted = Color(0xFF4C566A); // nord3
  static const text2 = Color(0xFFD8DEE9); // nord4
  static const text1 = Color(0xFFECEFF4); // nord6
  static const accent = Color(0xFFA3BE8C); // nord14 green
  static const success = Color(0xFFA3BE8C);
  static const info = Color(0xFF88C0D0); // nord8
  static const frost3 = Color(0xFF88C0D0);
  static const frost4 = Color(0xFF81A1C1);
  static const primary = Color(0xFF5E81AC); // nord10
  static const error = Color(0xFFBF616A); // nord11
  static const warning = Color(0xFFEBCB8B); // nord13
}

ThemeData buildNordTheme() {
  final scheme = ColorScheme.dark(
    primary: Nord.accent,
    secondary: Nord.info,
    tertiary: Nord.primary,
    surface: Nord.surface,
    onSurface: Nord.text1,
    onSurfaceVariant: Nord.text2,
    onPrimary: Nord.bg,
    onSecondary: Nord.bg,
    error: Nord.error,
    onError: Nord.bg,
    outline: Nord.border,
    outlineVariant: Nord.border,
    surfaceContainerHighest: Nord.border,
    surfaceContainer: Nord.surface,
    scrim: Nord.bg,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Nord.bg,
    canvasColor: Nord.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Nord.bg,
      foregroundColor: Nord.text1,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: Nord.border, thickness: 0.5),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Nord.surface,
      hintStyle: const TextStyle(color: Nord.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Nord.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Nord.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Nord.info, width: 1.2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Nord.surface,
      indicatorColor: Nord.accent.withValues(alpha: 0.22),
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Nord.accent : Nord.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? Nord.text1 : Nord.muted,
        ),
      ),
    ),
  );
}