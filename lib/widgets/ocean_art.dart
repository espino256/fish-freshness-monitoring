import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/app_theme.dart';
import 'neumorphic_card.dart';

class OceanArt extends StatelessWidget {
  const OceanArt({super.key, this.height = 230});

  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final narrow = constraints.maxWidth < 360;
      return SizedBox(
        height: compact ? 210 : height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SvgPicture.asset(
                'assets/images/ocean_hero.svg',
                fit: BoxFit.cover,
                semanticsLabel: 'Original AquaSense ocean illustration',
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xAA0A202C), Color(0x220A202C)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 16 : 22),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusPill(
                          label: narrow ? 'RESEARCH' : 'RESEARCH MONITORING',
                          color: AppColors.mint,
                          icon: Icons.water_drop_outlined,
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        Text(
                          compact
                              ? 'Welcome to AquaSense.'
                              : 'Clarity beneath the surface.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: compact ? 22 : 27,
                              ),
                        ),
                        SizedBox(height: compact ? 4 : 7),
                        Text(
                          compact
                              ? 'Fish Freshness Monitoring System'
                              : 'Fish Freshness Monitoring System · '
                                    'Real pH and image observations, '
                                    'kept independent.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: compact ? 12 : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
