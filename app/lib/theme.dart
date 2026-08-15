import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

TextStyle orbitron({double fontSize = 14, Color? color, FontWeight? fontWeight, double? letterSpacing}) {
  return AppTheme.orbitron(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing);
}

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

class AppHeader extends StatelessWidget {
  final IconData? trailing;
  final VoidCallback? onTrailingTap;
  final String screenLabel;

  const AppHeader({
    Key? key, 
    this.trailing, 
    this.onTrailingTap, 
    required this.screenLabel
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(screenLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailingTap,
              child: Icon(trailing, color: Colors.white),
            ),
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

class ServerPill extends StatelessWidget {
  final String? title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final Color pingColor;
  final String? code;
  final String? name;
  final String? pingLabel;
  final Widget? trailing;

  const ServerPill({
    Key? key,
    this.title,
    required this.subtitle,
    this.isSelected = false,
    required this.onTap,
    this.pingColor = AppColors.success,
    this.code,
    this.name,
    this.pingLabel,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String displayTitle = name ?? title ?? 'Сервер';
    final String displaySubtitle = pingLabel != null ? '$subtitle • $pingLabel' : subtitle;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1E1E1E) : const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? AppColors.violetGlow : AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: code != null 
            ? Text(code!, style: const TextStyle(fontSize: 22)) 
            : const Icon(Icons.dns_rounded, color: AppColors.textDim),
        title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        subtitle: Text(displaySubtitle, style: const TextStyle(color: AppColors.textDim)),
        trailing: trailing ?? Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: pingColor),
        ),
      ),
    );
  }
}

class StatMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Widget? icon;

  const StatMiniCard({
    Key? key,
    required this.label,
    required this.value,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  final String label;
  final dynamic icon;
  final VoidCallback onTap;

  const PillButton({
    Key? key,
    required this.label,
    required this.icon,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    if (icon is IconData) {
      iconWidget = Icon(icon as IconData, size: 16);
    } else if (icon is String) {
      iconWidget = Text(icon as String, style: const TextStyle(fontSize: 14));
    } else {
      iconWidget = const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
      onPressed: onTap,
      icon: iconWidget,
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
