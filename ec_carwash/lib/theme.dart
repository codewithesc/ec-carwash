import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get lightTheme {
    // Use Poppins with Roboto as fallback for special characters like ₱
    final baseTextTheme = GoogleFonts.poppinsTextTheme();
    final textThemeWithFallback = baseTextTheme.apply(
      fontFamilyFallback: const ['Roboto'],
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.yellow,
        brightness: Brightness.light,
        primary: Colors.yellow[700],
        secondary: Colors.black,
      ),
      fontFamily: 'Poppins',
      fontFamilyFallback: const ['Roboto'],
      textTheme: textThemeWithFallback,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellow,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.yellow[700],
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
    );
  }
}
