import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB300);
  static const Color danger = Color(0xFFFF5252);
  static const Color textDim = Color(0xB3FFFFFF);
  static const Color violetGlow = Color(0xFFB026FF);
  static const Color violet = Color(0xFF7000FF);
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

  static TextStyle orbitron({double fontSize = 14, Color? color, FontWeight? fontWeight, double? letterSpacing}) {
    return GoogleFonts.orbitron(
      fontSize: fontSize,
      color: color ?? Colors.white,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

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
    );
  }
}

// --- Совместимые UI-Kit виджеты для экранов приложения ---

class AppHeader extends StatelessWidget {
  final IconData? trailing;
  final String screenLabel;
  const AppHeader({Key? key, this.trailing, required this.screenLabel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(screenLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (trailing != null) Icon(trailing, color: Colors.white),
        ],
      ),
    );
  }
}

class NeonBadge extends StatelessWidget {
  final String label;
  const NeonBadge(this.label, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.success.withOpacity(0.5)),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
      child: Text(title, style: const TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}

class NeonToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const NeonToggle({Key? key, required this.value, required this.onChanged}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.success,
      activeTrackColor: AppColors.success.withOpacity(0.3),
      inactiveThumbColor: Colors.grey,
      inactiveTrackColor: Colors.white10,
    );
  }
}
