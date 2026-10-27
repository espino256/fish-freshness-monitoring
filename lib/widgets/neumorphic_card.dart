import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class NeumorphicCard extends StatelessWidget {
  const NeumorphicCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF42636B).withValues(alpha: 0.09),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
      ],
    );
    if (action == null) return text;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 440
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 12), action!],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: text),
                action!,
              ],
            ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    super.key,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final semanticIcon =
        icon ??
        switch (label.toLowerCase()) {
          'fresh' => Icons.check_circle_outline_rounded,
          'moderate' => Icons.change_circle_outlined,
          'spoiled' => Icons.warning_amber_rounded,
          'review required' => Icons.help_outline_rounded,
          'no data' => Icons.remove_circle_outline_rounded,
          'sensor offline' => Icons.sensors_off_rounded,
          'processing' => Icons.hourglass_top_rounded,
          _ => null,
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (semanticIcon != null) ...[
            Icon(semanticIcon, size: 15, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
