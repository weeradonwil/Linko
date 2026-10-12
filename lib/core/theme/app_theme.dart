import 'package:flutter/material.dart';

/// Theme tokens shared by every screen.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFFFF4F64);
  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightInput = Color(0xFFF0F2F5);
  static const Color lightText = Color(0xFF171A21);
  static const Color lightSecondary = Color(0xFF667085);

  static const Color darkBackground = Color(0xFF0F1724);
  static const Color darkCard = Color(0xFF1B2638);
  static const Color darkInput = Color(0xFF253247);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSecondary = Color(0xFFAABAC3);

  static ThemeData light() => _buildTheme(
    brightness: Brightness.light,
    background: lightBackground,
    card: lightCard,
    input: lightInput,
    text: lightText,
    secondary: lightSecondary,
  );

  static ThemeData dark() => _buildTheme(
    brightness: Brightness.dark,
    background: darkBackground,
    card: darkCard,
    input: darkInput,
    text: darkText,
    secondary: darkSecondary,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color card,
    required Color input,
    required Color text,
    required Color secondary,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      surface: card,
      onSurface: text,
      onSurfaceVariant: secondary,
      outline: secondary,
      outlineVariant: secondary.withValues(alpha: 0.28),
      surfaceContainerLowest: background,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: input,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
      textTheme: baseTextTheme.apply(
        bodyColor: text,
        displayColor: text,
      ).copyWith(
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
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: input,
        side: BorderSide(color: secondary.withValues(alpha: 0.22)),
        labelStyle: TextStyle(color: text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerColor: secondary.withValues(alpha: 0.22),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
