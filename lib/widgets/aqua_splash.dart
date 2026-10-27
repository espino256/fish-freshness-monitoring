import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'aqua_brand_mark.dart';

class AquaSplash extends StatelessWidget {
  const AquaSplash({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navyDeep, AppColors.ocean, AppColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -90,
            right: -60,
            child: _GlowOrb(size: 280, opacity: 0.11),
          ),
          const Positioned(
            bottom: -130,
            left: -80,
            child: _GlowOrb(size: 330, opacity: 0.12),
          ),
          Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 700),
              tween: Tween(begin: 0.92, end: 1),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AquaBrandMark(size: 76),
                  SizedBox(height: 22),
                  Text(
                    'AquaSense',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Fish Freshness Monitoring System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFD1EFED),
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 34),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.mint,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Preparing your monitoring environment...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB9D7D9), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.aqua.withValues(alpha: opacity),
    ),
  );
}
