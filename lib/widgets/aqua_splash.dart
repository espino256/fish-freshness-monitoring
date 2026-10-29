import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'aqua_brand_mark.dart';
import 'soft_ui.dart';

class AquaSplash extends StatefulWidget {
  const AquaSplash({
    super.key,
    this.onSplashComplete,
    this.duration = const Duration(milliseconds: 2500),
  });
  final VoidCallback? onSplashComplete;
  final Duration duration;
  @override
  State<AquaSplash> createState() => _AquaSplashState();
}

class _AquaSplashState extends State<AquaSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    if (widget.onSplashComplete != null) {
      _timer = Timer(widget.duration, widget.onSplashComplete!);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: OceanBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: .96, end: 1.04).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: const SoftPanel(
                    padding: EdgeInsets.all(30),
                    child: AquaBrandMark(size: 80),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'AquaSense',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fish Freshness Monitoring System',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mint),
                ),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    color: AppColors.mint,
                    backgroundColor: AppColors.ocean,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Preparing your monitoring workspace…',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
