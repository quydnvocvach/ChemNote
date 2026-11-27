import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class AppTheme {
  static const PageTransitionsTheme _smoothPageTransitions =
      PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  // Bảng màu Obsidian Dark theo phong cách Huawei Notes × GoodNotes 6
  static const Color obsidianBg = Color(0xFF0B0C10);
  static const Color obsidianSurface = Color(0xFF16181D);
  static const Color obsidianCard = Color(0xFF22252E);
  static const Color obsidianBorder = Color(0xFF2C313E);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentTeal = Color(0xFF14B8A6);

  // Bảng màu Light Mode êm mắt (Warm Paper-Stone / Alabaster giảm chói)
  static const Color lightBg = Color(0xFFEEECE6);
  static const Color lightSurface = Color(0xFFF6F4EE);
  static const Color lightCard = Color(0xFFE7E3DA);
  static const Color lightBorder = Color(0xFFD6D0C4);
  static const Color lightInk = Color(0xFF1F2329);
  static const Color lightMuted = Color(0xFF5F6670);
  static const Color primaryNavy = Color(0xFF1E3A5F);

  static const List<int> notebookCoverColors = [
    0xFF1E3A5F, // Navy học thuật
    0xFF0F766E, // Xanh lục bảo (Hóa học)
    0xFF1D4ED8, // Xanh coban
    0xFF4C1D95, // Tím đậm
    0xFF9F1239, // Đỏ rượu vang
    0xFF7C2D12, // Nâu đất ấm
    0xFF365314, // Xanh rêu
    0xFF334155, // Xám đá phiến
  ];

  static const List<int> folderColors = [
    0xFF3B82F6,
    0xFF14B8A6,
    0xFFF59E0B,
    0xFFEF4444,
    0xFF8B5CF6,
    0xFF64748B,
  ];

  static ThemeData darkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentBlue,
      brightness: Brightness.dark,
      primary: accentBlue,
      secondary: accentTeal,
      surface: obsidianSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      pageTransitionsTheme: _smoothPageTransitions,
      scaffoldBackgroundColor: obsidianBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: obsidianSurface,
        foregroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFFF1F5F9),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: obsidianCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: obsidianBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: obsidianBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: obsidianSurface,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentBlue,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: obsidianCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: obsidianBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: obsidianBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentBlue, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: obsidianBorder,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: obsidianCard,
        selectedColor: accentBlue.withValues(alpha: 0.22),
        side: const BorderSide(color: obsidianBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryNavy,
      brightness: Brightness.light,
      primary: const Color(0xFF2563EB),
      secondary: accentTeal,
      surface: lightSurface,
      onSurface: lightInk,
      onSurfaceVariant: lightMuted,
      surfaceContainerHighest: lightCard,
      outlineVariant: lightBorder,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      pageTransitionsTheme: _smoothPageTransitions,
      scaffoldBackgroundColor: lightBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: lightInk,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightInk,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: lightBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentBlue,
        foregroundColor: Colors.white,
        elevation: 3,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentBlue, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightCard,
        selectedColor: accentBlue.withValues(alpha: 0.16),
        side: const BorderSide(color: lightBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
