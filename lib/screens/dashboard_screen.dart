import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/telemetry.dart';
import '../services/demo_session.dart';
import '../widgets/soft_ui.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.readings, this.onRefresh});
  final Stream<List<Telemetry>> readings;
  final VoidCallback? onRefresh;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = DemoScope.maybeOf(context);
    final demo = session?.enabled == true;
    return StreamBuilder<List<Telemetry>>(
      stream: widget.readings,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Monitoring overview',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              demo
                  ? 'SIMULATED · Explore pH, voltage and hardware indicators.'
                  : 'ESP32 DevKit V1 · GPIO34 · 12-bit ADC',
            ),
            const SizedBox(height: 24),
            if (snapshot.hasError)
              SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Unable to read telemetry. Check network, email verification, and database rules.',
                    ),
                    const SizedBox(height: 16),
                    SoftButton(
                      label: 'Refresh telemetry',
                      icon: Icons.refresh,
                      onPressed: () {
                        widget.onRefresh?.call();
                        if (widget.onRefresh == null) {
                          showNotice(
                            context,
                            'Check your connection and retry.',
                          );
                        }
                      },
                    ),
                  ],
                ),
              )
            else if (!snapshot.hasData)
              const LinearProgressIndicator()
            else if (rows.isEmpty)
              const SoftPanel(
                child: Text(
                  'No telemetry yet. Calibrate and connect the pH device.',
                ),
              )
            else
              for (final reading in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _ReadingCard(reading: reading, session: session),
                ),
            if (demo)
              SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'pH simulator',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Drag the slider to test each freshness range. No sensor command is sent.',
                    ),
                    Slider(
                      key: const Key('ph-slider'),
                      value: session!.ph,
                      min: 0,
                      max: 14,
                      divisions: 140,
                      label: session.ph.toStringAsFixed(1),
                      onChanged: session.setPh,
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final (label, value) in [
                          ('Fresh · 6.3', 6.3),
                          ('Moderate · 6.8', 6.8),
                          ('Spoiled · 7.4', 7.4),
                        ])
                          SoftButton(
                            label: label,
                            onPressed: () => session.setPh(value),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic simulation'),
                      value: session.autoTelemetry,
                      onChanged: session.setAutomatic,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            SoftButton(
              label: 'Refresh telemetry',
              icon: Icons.refresh,
              onPressed: () {
                if (widget.onRefresh != null) {
                  widget.onRefresh!();
                } else if (demo) {
                  session!.refresh();
                } else {
                  showNotice(
                    context,
                    'Telemetry listens continuously. Check the device connection.',
                  );
                }
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Nominal V = ADC × 3.3 / 4095. Measured voltage uses ADC calibration. pH: Fresh < 6.5; Moderate 6.5–<7.2; Spoiled ≥ 7.2. Estimates require species-specific validation and do not certify food safety.',
            ),
          ],
        );
      },
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.reading, this.session});
  final Telemetry reading;
  final DemoSession? session;
  @override
  Widget build(BuildContext context) {
    final demo = session?.enabled == true;
    final stale = !demo && reading.isStale(DateTime.now().toUtc());
    final color = switch (reading.status) {
      FishStatus.fresh => AppColors.fresh,
      FishStatus.moderate => AppColors.moderate,
      FishStatus.spoiled => AppColors.spoiled,
    };
    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                reading.deviceId,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Chip(
                label: Text(
                  stale
                      ? 'STALE · check device connection'
                      : '${demo ? 'DEMO' : 'LIVE'} · ${reading.status.name.toUpperCase()}',
                ),
                side: BorderSide.none,
                backgroundColor: color.withValues(alpha: .12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'pH ${reading.ph.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w700,
              color: stale ? AppColors.muted : color,
            ),
          ),
          Text('ADC ${reading.adcRaw.toStringAsFixed(1)} / 4095'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Text('Nominal ${reading.nominalVoltage.toStringAsFixed(3)} V'),
              Text('Measured ${reading.measuredVoltage.toStringAsFixed(3)} V'),
            ],
          ),
          const SizedBox(height: 8),
          Text('Updated ${reading.timestamp.toLocal()}'),
          const SizedBox(height: 24),
          Row(
            children: [
              for (final (status, pin, ledColor) in [
                (FishStatus.fresh, 27, Colors.green),
                (FishStatus.moderate, 25, Colors.amber),
                (FishStatus.spoiled, 26, Colors.red),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Semantics(
                      label:
                          '${status.name} GPIO$pin ${(demo ? session!.leds[pin]! : !stale && reading.status == status) ? 'on' : 'off'}',
                      child: SoftPanel(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    (demo
                                        ? session!.leds[pin]!
                                        : !stale && reading.status == status)
                                    ? ledColor
                                    : const Color(0xFFADBEC4),
                                boxShadow:
                                    (demo
                                        ? session!.leds[pin]!
                                        : !stale && reading.status == status)
                                    ? [
                                        BoxShadow(
                                          color: ledColor.withValues(
                                            alpha: .35,
                                          ),
                                          blurRadius: 16,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [],
                              ),
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                status.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              key: Key('led-$pin'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(32, 44),
                              ),
                              onPressed: () {
                                if (demo) {
                                  session!.toggleLed(pin);
                                } else {
                                  showNotice(
                                    context,
                                    'GPIO$pin is controlled by physical pH firmware. Use demo mode to test LED toggles.',
                                  );
                                }
                              },
                              child: Text(
                                'GPIO$pin',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (demo && session!.manualLeds)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Manual LED test active. The next simulated reading or refresh restores automatic classification.',
              ),
            ),
        ],
      ),
    );
  }
}
