import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

const oceanBackgroundAsset = 'assets/images/ocean_water.png';
const softShadows = [
  BoxShadow(color: Color(0xEEFFFFFF), offset: Offset(-5, -5), blurRadius: 14),
  BoxShadow(color: Color(0x33637987), offset: Offset(6, 7), blurRadius: 16),
];

class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.inset = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool inset;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: inset ? const Color(0xFFDDE7EA) : AppColors.canvas,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .65)),
      boxShadow: inset
          ? const [
              BoxShadow(
                color: Color(0x225A7885),
                offset: Offset(2, 3),
                blurRadius: 5,
              ),
            ]
          : softShadows,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class SoftButton extends StatefulWidget {
  const SoftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool primary, busy;
  @override
  State<SoftButton> createState() => _SoftButtonState();
}

class _SoftButtonState extends State<SoftButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    decoration: BoxDecoration(
      color: widget.primary ? AppColors.teal : AppColors.canvas,
      borderRadius: BorderRadius.circular(16),
      boxShadow: _pressed || widget.busy ? const [] : softShadows,
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onTap: () {
          if (!widget.busy) widget.onPressed();
        },
        child: Semantics(
          button: true,
          enabled: !widget.busy,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.primary ? Colors.white : AppColors.teal,
                    ),
                  )
                else if (widget.icon != null)
                  Icon(
                    widget.icon,
                    size: 20,
                    color: widget.primary ? Colors.white : AppColors.teal,
                  ),
                if (widget.busy || widget.icon != null)
                  const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.primary ? Colors.white : AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class OceanBackdrop extends StatelessWidget {
  const OceanBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        oceanBackgroundAsset,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.navyDeep),
      ),
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE6102D3A), Color(0xD3123F50), Color(0xED102D3A)],
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

class OceanPage extends StatelessWidget {
  const OceanPage({super.key, required this.child, this.maxWidth = 1180});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 28),
          child: child,
        ),
      ),
    ),
  );
}

class SoftField extends StatelessWidget {
  const SoftField({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(16),
      boxShadow: softShadows,
    ),
    child: child,
  );
}

void showNotice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.sizeOf(context).width < 1000 ? 100 : 24,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
