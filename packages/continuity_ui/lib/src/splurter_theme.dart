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
    primary: Color(0xFF6CDBAC),
    onPrimary: Color(0xFF003828),
    primaryContainer: Color(0xFF005140),
    onPrimaryContainer: Color(0xFF89F8C9),
    secondary: Color(0xFFB5CCBD),
    onSecondary: Color(0xFF273829),
    secondaryContainer: Color(0xFF3D4F43),
    onSecondaryContainer: Color(0xFFD0E8D9),
    tertiary: Color(0xFFA9CDE0),
    onTertiary: Color(0xFF023440),
    tertiaryContainer: Color(0xFF244B5B),
    onTertiaryContainer: Color(0xFFC4EAFB),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF191C1A),
    onSurface: Color(0xFFE2E3DF),
    onSurfaceVariant: Color(0xFFBFC9C2),
    outline: Color(0xFF89938C),
    outlineVariant: Color(0xFF3F4944),
    surfaceContainerHighest: Color(0xFF3F4944),
  );

  static ThemeData get light => ThemeData(
    colorScheme: _lightColorScheme,
    useMaterial3: true,
    fontFamily: 'SFProText',
  );

  static ThemeData get dark => ThemeData(
    colorScheme: _darkColorScheme,
    useMaterial3: true,
    fontFamily: 'SFProText',
  );
}
