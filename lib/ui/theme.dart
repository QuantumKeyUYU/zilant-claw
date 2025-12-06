import 'package:flutter/material.dart';

ThemeData buildTheme() {
  const primaryColor = Color(0xFF3DBE8B);
  const background = Color(0xFF0E1525);
  const cardColor = Color(0xFF162034);

  return ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: Color(0xFF6EE7B7),
      surface: cardColor,
      background: background,
    ),
    scaffoldBackgroundColor: background,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(color: Colors.white70),
    ),
  );
}
