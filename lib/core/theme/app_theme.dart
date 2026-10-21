// รวมสีและรูปแบบ Material 3 สำหรับทุกหน้าจอในโหมดสว่างและมืด
import 'package:flutter/material.dart';

import 'theme_accent.dart';

/// แหล่งกำหนดสี พื้นหลัง ตัวอักษร และวิดเจ็ตกลางของแอป
class AppTheme {
  AppTheme._();

  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightInput = Color(0xFFF0F2F5);
  static const Color lightText = Color(0xFF171A21);
  static const Color lightSecondary = Color(0xFF586273);

  static const Color darkBackground = Color(0xFF0F1724);
  static const Color darkCard = Color(0xFF1B2638);
  static const Color darkInput = Color(0xFF253247);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSecondary = Color(0xFFAABAC3);

  static ThemeData light({ThemeAccent accent = ThemeAccent.linko}) =>
      _buildTheme(
        brightness: Brightness.light,
        accent: accent.light,
        background: lightBackground,
        card: lightCard,
        input: lightInput,
        text: lightText,
        secondary: lightSecondary,
      );

  static ThemeData dark({ThemeAccent accent = ThemeAccent.linko}) =>
      _buildTheme(
        brightness: Brightness.dark,
        accent: accent.dark,
        background: darkBackground,
        card: darkCard,
        input: darkInput,
        text: darkText,
        secondary: darkSecondary,
      );

  // สร้างธีมจากโครงเดียวกัน เพื่อให้สองโหมดต่างกันเฉพาะชุดสีและความสว่างที่ส่งเข้ามา
  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color accent,
    required Color background,
    required Color card,
    required Color input,
    required Color text,
    required Color secondary,
  }) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          // เลือกสีข้อความที่ contrast สูงกว่า แทนการใช้ขาวเสมอบนสีเหลืองหรือสีอ่อน
          onPrimary: _foregroundOn(accent),
          surface: card,
          onSurface: text,
          onSurfaceVariant: secondary,
          outline: secondary,
          outlineVariant: secondary.withValues(alpha: 0.28),
          surfaceContainerLowest: background,
          surfaceContainerLow: card,
          surfaceContainer: card,
          surfaceContainerHigh: input,
          surfaceContainerHighest: input,
          surfaceBright: card,
          surfaceDim: background,
        );

    final baseTextTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: card,
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: baseTextTheme
          .apply(bodyColor: text, displayColor: text)
          .copyWith(
            bodySmall: baseTextTheme.bodySmall?.copyWith(color: secondary),
            labelSmall: baseTextTheme.labelSmall?.copyWith(color: secondary),
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        hintStyle: TextStyle(color: secondary),
        labelStyle: TextStyle(color: secondary),
        prefixIconColor: secondary,
        suffixIconColor: secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: secondary.withValues(alpha: 0.22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: input,
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(color: secondary.withValues(alpha: 0.22)),
        labelStyle: TextStyle(color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerColor: secondary.withValues(alpha: 0.22),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.22),
        selectionHandleColor: accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // เลือกคู่สีจาก luminance จริง; ทั้งสองโหมดใช้คู่สีเดียวกับปุ่มและ bubble แชท
  static Color _foregroundOn(Color background) {
    final luminance = background.computeLuminance();
    final whiteContrast = 1.05 / (luminance + 0.05);
    final darkContrast =
        (luminance + 0.05) / (lightText.computeLuminance() + 0.05);
    return whiteContrast >= darkContrast ? Colors.white : lightText;
  }

  /// แถบวิดีโอเต็มจออยู่บนพื้นดำเสมอ จึงใช้เฉดอ่อนแทนสีเข้มของ Light Mode เมื่อจำเป็น
  static Color mediaProgressColor(ColorScheme colors) {
    if (colors.primary.computeLuminance() >= 0.175) return colors.primary;
    if (colors.primaryContainer.computeLuminance() >= 0.175) {
      return colors.primaryContainer;
    }
    return Colors.white;
  }
}
