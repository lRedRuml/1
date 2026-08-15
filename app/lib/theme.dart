import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color success = Color(0xFF00E676);
  static const Color danger = Color(0xFFFF5252);
  static const Color textDim = Color(0xB3FFFFFF);
  static const Color violetGlow = Color(0xFFB026FF);
  static const Color violet2 = Color(0xFFE042E0);
  static const Color border = Color(0xFF333333);

  static List<BoxShadow> glow(Color color, {double blur = 8, double alpha = 0.8}) {
    return [
      BoxShadow(
        color: color.withOpacity(alpha),
        blurRadius: blur,
        spreadRadius: 1,
      )
    ];
  }
}

class AppTheme {
  static const Color backgroundColor = Color(0xFF000000);
  static const Color primaryColor = Color(0xFFB026FF);
  static const Color secondaryColor = Color(0xFFE042E0);

  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark();
    return baseTheme.copyWith(
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        background: backgroundColor,
        surface: Color(0xFF121212),
      ),
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      cardTheme: const CardTheme(
        color: Color(0xFF1E1E1E),
        elevation: 2,
        margin: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      ),
    );
  }
}
