import 'package:flutter/material.dart';

/// Dark-first palette: ink ground, hot coral for action, mint for health data.
class SoColors {
  static const ink = Color(0xFF0D1015);
  static const surface = Color(0xFF161B23);
  static const surface2 = Color(0xFF1F2632);
  static const line = Color(0xFF2B3442);
  static const coral = Color(0xFFFF5A47);
  static const coralSoft = Color(0x33FF5A47);
  static const mint = Color(0xFF5CF0C0);
  static const mintSoft = Color(0x335CF0C0);
  static const amber = Color(0xFFFFC65C);
  static const violet = Color(0xFFA78BFA);
  static const text = Color(0xFFF3F5F8);
  static const muted = Color(0xFF9AA5B5);
}

ThemeData buildRitmoTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = const ColorScheme.dark(
    primary: SoColors.coral,
    onPrimary: Colors.white,
    secondary: SoColors.mint,
    onSecondary: SoColors.ink,
    tertiary: SoColors.amber,
    surface: SoColors.surface,
    onSurface: SoColors.text,
    surfaceContainerHighest: SoColors.surface2,
    outline: SoColors.line,
    error: Color(0xFFFF7A7A),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: SoColors.ink,
    canvasColor: SoColors.ink,
    textTheme: base.textTheme.apply(bodyColor: SoColors.text, displayColor: SoColors.text).copyWith(
          headlineMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1, color: SoColors.text),
          titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: SoColors.text),
          titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SoColors.text),
          bodyMedium: const TextStyle(fontSize: 14.5, height: 1.4, color: SoColors.text),
          bodySmall: const TextStyle(fontSize: 12.5, color: SoColors.muted),
          labelSmall: const TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: SoColors.muted),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SoColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: SoColors.text),
    ),
    cardTheme: CardThemeData(
      color: SoColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: SoColors.line)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: SoColors.surface2,
      selectedColor: SoColors.coral,
      side: BorderSide.none,
      labelStyle: const TextStyle(color: SoColors.text, fontSize: 13, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SoColors.surface2,
      hintStyle: const TextStyle(color: SoColors.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: SoColors.coral, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SoColors.coral,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SoColors.text,
        side: const BorderSide(color: SoColors.line),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: SoColors.mint, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SoColors.surface,
      indicatorColor: SoColors.coralSoft,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? SoColors.text : SoColors.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? SoColors.coral : SoColors.muted,
          )),
    ),
    dividerColor: SoColors.line,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: SoColors.surface2, contentTextStyle: TextStyle(color: SoColors.text)),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: SoColors.surface, surfaceTintColor: Colors.transparent, showDragHandle: true),
    dialogTheme: const DialogThemeData(backgroundColor: SoColors.surface, surfaceTintColor: Colors.transparent),
    sliderTheme: const SliderThemeData(activeTrackColor: SoColors.coral, thumbColor: SoColors.coral, inactiveTrackColor: SoColors.line),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: SoColors.coral),
  );
}
