import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class AquaBrandMark extends StatelessWidget {
  const AquaBrandMark({super.key, this.size = 54});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.aqua, AppColors.teal],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(size * 0.32),
      boxShadow: [
        BoxShadow(
          color: AppColors.teal.withValues(alpha: 0.28),
          blurRadius: 20,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: Icon(Icons.waves_rounded, size: size * 0.62, color: Colors.white),
  );
}
