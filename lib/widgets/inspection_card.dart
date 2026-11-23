import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../core/app_theme.dart';

class ResponsivePageList extends StatelessWidget {
  const ResponsivePageList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minimum = constraints.maxWidth < 400 ? 12.0 : 24.0;
      final inset = math.max(minimum, (constraints.maxWidth - 1280) / 2);
      return ListView(
        padding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
        children: children,
      );
    },
  );
}

/// Content-sized cards keep text accessible at narrow widths and large scales.
class InspectionCard extends StatelessWidget {
  const InspectionCard({
    super.key,
    required this.child,
    this.accent = false,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final bool accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: accent ? null : Colors.white,
      gradient: accent
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF0FAF8), Color(0xFFDCF0EF)],
            )
          : null,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: accent ? const Color(0xFFB7DBD7) : const Color(0xFFDDE8EA),
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .045),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class InspectionHeading extends StatelessWidget {
  const InspectionHeading({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.teal.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.teal, size: 24),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class InspectionBadge extends StatelessWidget {
  const InspectionBadge({
    super.key,
    required this.label,
    this.color = AppColors.teal,
  });
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
