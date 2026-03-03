import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color bg = Color(0xFF060810);
  static const Color surface = Color(0xFF0E1219);
  static const Color surface2 = Color(0xFF141A24);
  static const Color surface3 = Color(0xFF1C2534);
  static const Color green = Color(0xFF00FF87);
  static const Color green2 = Color(0xFF00E676);
  static const Color greenDim = Color(0x1400FF87);
  static const Color red = Color(0xFFFF4560);
  static const Color redDim = Color(0x1AFF4560);
  static const Color gold = Color(0xFFFFD700);
  static const Color blue = Color(0xFF4FC3F7);
  static const Color purple = Color(0xFFB388FF);
  static const Color silver = Color(0xFFA8B8C8);
  static const Color textPrimary = Color(0xFFEEF2F7);
  static const Color textMuted = Color(0xFF5A7A96);
  static const Color border = Color(0x0FFFFFFF);
  static const Color border2 = Color(0x1AFFFFFF);
  static const Color greenBorder = Color(0x3300FF87);
  static const Color surface1 = Color(0xFF0E1219);
  static const Color text = Color(0xFFEEF2F7);

  /// Format a number as currency: $1,234.56
  /// Use [decimals] to control precision (default 2).
  static String currency(num value, {int decimals = 2}) {
    final isNegative = value < 0;
    final abs = value.abs();
    final fixed = abs.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Add commas to integer part
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${isNegative ? '-' : ''}\$$buf$decPart';
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: AppTheme.text, displayColor: AppTheme.text),
      colorScheme: const ColorScheme.dark(
        primary: green,
        secondary: green,
        surface: surface,
        error: red,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: green,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: green, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
    );
  }
}
