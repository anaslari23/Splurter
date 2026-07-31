import 'package:flutter/material.dart';

class SplurterTheme {
  static const _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF006C4E),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF89F8C9),
    onPrimaryContainer: Color(0xFF002114),
    secondary: Color(0xFF4D6357),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD0E8D9),
    onSecondaryContainer: Color(0xFF1A211E),
    tertiary: Color(0xFF3D6373),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFC4EAFB),
    onTertiaryContainer: Color(0xFF001F2A),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF8FDF7),
    onSurface: Color(0xFF191C1A),
    onSurfaceVariant: Color(0xFF3F4944),
    outline: Color(0xFF6F7974),
    outlineVariant: Color(0xFFBFC9C2),
    surfaceContainerHighest: Color(0xFFDDE5DD),
  );

  static const _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF6366F1), // Indigo accent
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF312E81),
    onPrimaryContainer: Color(0xFFE0E7FF),
    secondary: Color(0xFF06B6D4), // Cyan highlight
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF164E63),
    onSecondaryContainer: Color(0xFFCFFAFE),
    tertiary: Color(0xFFA855F7), // Purple accent
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFF581C87),
    onTertiaryContainer: Color(0xFFF3E8FF),
    error: Color(0xFFF87171),
    onError: Colors.black,
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF0F172A), // Slate 900 dark background
    onSurface: Color(0xFFF8FAFC),
    onSurfaceVariant: Color(0xFF94A3B8),
    outline: Color(0xFF334155),
    outlineVariant: Color(0xFF1E293B),
    surfaceContainerHighest: Color(0xFF1E293B),
  );

  static ThemeData get light => ThemeData(
    colorScheme: _lightColorScheme,
    useMaterial3: true,
    fontFamily: 'SFProText',
  );

  static ThemeData get dark => ThemeData(
    colorScheme: _darkColorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0B0F17),
    cardTheme: CardThemeData(
      color: const Color(0xFF161F30).withValues(alpha: 0.75),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155), width: 1),
      ),
    ),
    fontFamily: 'SFProText',
  );
}
