import 'package:flutter/material.dart';
import '../theme.dart';

class NeonServerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isOnline;
  final int? latency;
  final Color pingColor;
  final VoidCallback? onTap;

  const NeonServerCard({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.isOnline,
    this.latency,
    this.pingColor = AppColors.success,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF121212),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? pingColor : AppColors.danger,
                    boxShadow: isOnline ? AppColors.glow(pingColor, blur: 6) : AppColors.glow(AppColors.danger, blur: 6),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textDim)),
                    ],
                  ),
                ),
                if (latency != null)
                  Text(
                    '${latency} ms',
                    style: TextStyle(color: isOnline ? pingColor : AppColors.danger, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NeonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const NeonCard({
    Key? key, 
    required this.child,
    this.margin,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: child,
    );
  }
}
