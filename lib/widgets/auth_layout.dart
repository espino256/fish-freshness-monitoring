import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'aqua_brand_mark.dart';
import 'soft_ui.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.back = false,
  });
  final String title, subtitle;
  final Widget child;
  final bool back;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: back
        ? AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('AquaSense'),
          )
        : null,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final form = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: SoftPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: AquaBrandMark(size: 54),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(subtitle),
                        const SizedBox(height: 24),
                        child,
                      ],
                    ),
                  ),
                );
                if (constraints.maxWidth < 900) return Center(child: form);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 64),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AQUASENSE / MONITORING WORKSPACE',
                              style: TextStyle(
                                color: AppColors.mint,
                                letterSpacing: 2,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Fresh insights.\nFrom water\nto workspace.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 52,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -2,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Live pH. Visual inspection. Clear decisions.\nYour fish freshness tools, connected in one place.',
                              style: TextStyle(
                                color: Color(0xFFD2E7EB),
                                height: 1.7,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    form,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
