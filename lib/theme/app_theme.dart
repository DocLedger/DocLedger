import 'package:flutter/material.dart';

/// Centralized app theme based on DocLedger logo
///
/// Primary: Light blue
/// Secondary/Accent: Red (cross)
/// Neutrals: Dark gray for headings
class AppTheme {
  static const Color _primaryBlue = Color(0xFF35B6F2); // logo light blue
  static const Color _primaryBlueDark = Color(0xFF1E9BD6);
  static const Color _accentRed = Color(0xFFE53935);
  static const Color _headingGray = Color(0xFF4A4A4A);
  static const Color _background = Color(0xFFF4F8FB); // dashboard bg
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _cardBorder = Color(0xFFE6EEF4);

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryBlue,
      primary: _primaryBlue,
      onPrimary: Colors.white,
      secondary: _accentRed,
      onSecondary: Colors.white,
      tertiary: _headingGray,
      brightness: Brightness.light,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _background,
      cardColor: _card,
      appBarTheme: AppBarTheme(
        backgroundColor: _background,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: _headingGray,
          fontWeight: FontWeight.w700,
        ),
      ),
      // Input decoration theme defined below
      chipTheme: base.chipTheme.copyWith(
        color: WidgetStateProperty.all(colorScheme.primaryContainer),
        labelStyle: base.textTheme.bodyMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: _primaryBlue.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.all(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: _headingGray,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: _headingGray,
          fontWeight: FontWeight.w700,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(color: _cardBorder),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: _cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _primaryBlueDark),
        ),
      ),
    );
  }
}

