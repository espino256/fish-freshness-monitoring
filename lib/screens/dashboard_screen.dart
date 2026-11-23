import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/telemetry.dart';
import '../services/demo_session.dart';
import '../widgets/soft_ui.dart';
import '../widgets/inspection_card.dart';
import '../widgets/live_ph_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.readings,
    this.historyReadings,
    this.onRefresh,
    this.telemetryUnavailableReason,
  });

  final Stream<List<Telemetry>> readings;
  final Stream<List<Telemetry>>? historyReadings;
  final VoidCallback? onRefresh;
  final String? telemetryUnavailableReason;

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
        final rows = (snapshot.data ?? <Telemetry>[])
            .where((r) => r.hasValidSensorValues)
            .toList();

        // If historyReadings is null, avoid subscribing twice to widget.readings
        if (widget.historyReadings == null) {
          return _buildContent(context, snapshot, rows, rows, session, demo);
        }

        return StreamBuilder<List<Telemetry>>(
          stream: widget.historyReadings!,
          builder: (context, historySnapshot) {
            final historyData = historySnapshot.hasError
                ? <Telemetry>[]
                : (historySnapshot.data ?? <Telemetry>[])
                      .where((r) => r.hasValidSensorValues)
                      .toList();
            return _buildContent(
              context,
              snapshot,
              rows,
              historyData,
              session,
              demo,
            );
          },
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<List<Telemetry>> snapshot,
    List<Telemetry> liveRows,
    List<Telemetry> historyRows,
    DemoSession? session,
    bool demo,
  ) {
    final activeLive = liveRows;
    final activeHistory = widget.telemetryUnavailableReason == null
        ? historyRows
        : <Telemetry>[];

    return ResponsivePageList(
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
        LivePhCard(
          snapshot: snapshot,
          unavailableReason: widget.telemetryUnavailableReason,
          simulated: demo,
          onRefresh: widget.onRefresh,
        ),
        const SizedBox(height: 24),
        if (!snapshot.hasError && widget.telemetryUnavailableReason == null)
          for (final reading in activeLive)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _ReadingCard(reading: reading, session: session),
            ),
        if (demo) ...[
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
        ],

        // Analytics & Visual Charts Section
        if (activeHistory.isEmpty)
          const SoftPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sensor history',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'No received history is available for charts. Readings appear after the calibrated sensor publishes data.',
                ),
              ],
            ),
          ),
        _AnalyticsOverviewCard(telemetryList: activeHistory),
        const SizedBox(height: 24),
        _TelemetryTrendChart(telemetryList: activeHistory),
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
                backgroundColor: (stale ? AppColors.muted : color).withValues(
                  alpha: .12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Physical GPIO indicators · existing firmware pH bands',
            style: TextStyle(color: AppColors.muted),
          ),
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

/// Key metrics overview and freshness distribution diagram
class _AnalyticsOverviewCard extends StatelessWidget {
  const _AnalyticsOverviewCard({required this.telemetryList});

  final List<Telemetry> telemetryList;

  @override
  Widget build(BuildContext context) {
    if (telemetryList.isEmpty) return const SizedBox.shrink();

    final total = telemetryList.length;
    final avgPh =
        telemetryList.map((e) => e.ph).reduce((a, b) => a + b) / total;
    final avgVoltage =
        telemetryList.map((e) => e.measuredVoltage).reduce((a, b) => a + b) /
        total;

    final freshCount = telemetryList
        .where((e) => e.status == FishStatus.fresh)
        .length;
    final moderateCount = telemetryList
        .where((e) => e.status == FishStatus.moderate)
        .length;
    final spoiledCount = telemetryList
        .where((e) => e.status == FishStatus.spoiled)
        .length;

    final freshPct = (freshCount / total * 100).round();

    final overallStatus = classifyPh(avgPh);
    final overallColor = switch (overallStatus) {
      FishStatus.fresh => AppColors.fresh,
      FishStatus.moderate => AppColors.moderate,
      FishStatus.spoiled => AppColors.spoiled,
    };

    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sensor history summary',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          InspectionBadge(
            label: 'Average firmware band: ${overallStatus.name.toUpperCase()}',
            color: overallColor,
          ),
          const SizedBox(height: 16),
          // Metric Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns =
                  ((constraints.maxWidth + 12) / (scale > 1.3 ? 230 : 170))
                      .floor()
                      .clamp(1, 4);
              final itemWidth =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _KpiStatBox(
                    width: itemWidth,
                    label: 'AVERAGE pH',
                    value: avgPh.toStringAsFixed(2),
                    unit: 'pH',
                    color: overallColor,
                    icon: Icons.analytics_outlined,
                  ),
                  _KpiStatBox(
                    width: itemWidth,
                    label: 'READINGS BELOW 6.5',
                    value: '$freshPct%',
                    unit: 'of received records',
                    color: AppColors.fresh,
                    icon: Icons.check_circle_outline,
                  ),
                  _KpiStatBox(
                    width: itemWidth,
                    label: 'TOTAL READINGS',
                    value: '$total',
                    unit: 'records',
                    color: AppColors.teal,
                    icon: Icons.dataset_outlined,
                  ),
                  _KpiStatBox(
                    width: itemWidth,
                    label: 'AVG VOLTAGE',
                    value: avgVoltage.toStringAsFixed(2),
                    unit: 'V',
                    color: AppColors.navy,
                    icon: Icons.bolt_outlined,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Firmware pH range distribution',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 10),
          // Distribution Bar Diagram
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  if (freshCount > 0)
                    Expanded(
                      flex: freshCount,
                      child: Container(color: AppColors.fresh),
                    ),
                  if (moderateCount > 0)
                    Expanded(
                      flex: moderateCount,
                      child: Container(color: AppColors.moderate),
                    ),
                  if (spoiledCount > 0)
                    Expanded(
                      flex: spoiledCount,
                      child: Container(color: AppColors.spoiled),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _DiagramLegendPill(
                label: 'Fresh',
                count: freshCount,
                pct: (freshCount / total * 100).toStringAsFixed(1),
                color: AppColors.fresh,
              ),
              _DiagramLegendPill(
                label: 'Moderate',
                count: moderateCount,
                pct: (moderateCount / total * 100).toStringAsFixed(1),
                color: AppColors.moderate,
              ),
              _DiagramLegendPill(
                label: 'Spoiled',
                count: spoiledCount,
                pct: (spoiledCount / total * 100).toStringAsFixed(1),
                color: AppColors.spoiled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiStatBox extends StatelessWidget {
  const _KpiStatBox({
    required this.width,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });
  final double width;
  final String label, value, unit;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: InspectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unit,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _DiagramLegendPill extends StatelessWidget {
  const _DiagramLegendPill({
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
  });

  final String label;
  final int count;
  final String pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$label: $count ($pct%)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Custom painted interactive telemetry trend chart
class _TelemetryTrendChart extends StatefulWidget {
  const _TelemetryTrendChart({required this.telemetryList});

  final List<Telemetry> telemetryList;

  @override
  State<_TelemetryTrendChart> createState() => _TelemetryTrendChartState();
}

class _TelemetryTrendChartState extends State<_TelemetryTrendChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.telemetryList.isEmpty) return const SizedBox.shrink();

    // Sort chronologically (oldest to newest)
    final sortedData = widget.telemetryList.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Display latest 36 points for clear curve visual matching design spec
    final points = sortedData.length > 36
        ? sortedData.sublist(sortedData.length - 36)
        : sortedData;

    final selectedIdx =
        (_selectedIndex != null &&
            _selectedIndex! >= 0 &&
            _selectedIndex! < points.length)
        ? _selectedIndex!
        : points.length - 1;

    final selected = points[selectedIdx];
    final selectedColor = switch (selected.status) {
      FishStatus.fresh => AppColors.fresh,
      FishStatus.moderate => AppColors.moderate,
      FishStatus.spoiled => AppColors.spoiled,
    };

    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historical pH curve (${points.length} points)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text('Received telemetry · latest 36 points'),
          const SizedBox(height: 10),
          InspectionBadge(
            label: 'pH ${selected.ph.toStringAsFixed(2)}',
            color: selectedColor,
          ),
          const SizedBox(height: 14),
          // Tooltip inspector bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_outlined, size: 16, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Point #${selectedIdx + 1}: ${selected.timestamp.toLocal().toString().substring(0, 19)} · pH ${selected.ph.toStringAsFixed(2)} (${selected.status.name.toUpperCase()}) · ${selected.measuredVoltage.toStringAsFixed(2)} V',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Interactive Custom Painter
          SizedBox(
            height: 200,
            width: double.infinity,
            child: GestureDetector(
              onTapDown: (details) =>
                  _onChartTouch(details.localPosition, points),
              onPanUpdate: (details) =>
                  _onChartTouch(details.localPosition, points),
              child: CustomPaint(
                painter: _TelemetryChartPainter(
                  readings: points,
                  selectedIndex: selectedIdx,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Zone Legend
          const Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _ZoneLegendItem(label: 'Fresh (<6.5)', color: AppColors.fresh),
              _ZoneLegendItem(
                label: 'Moderate (6.5–7.2)',
                color: AppColors.moderate,
              ),
              _ZoneLegendItem(
                label: 'Spoiled (≥7.2)',
                color: AppColors.spoiled,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onChartTouch(Offset pos, List<Telemetry> points) {
    if (points.isEmpty) return;
    const paddingLeft = 36.0;
    const paddingRight = 16.0;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final totalWidth = box?.size.width ?? 300;
    final chartWidth = totalWidth - paddingLeft - paddingRight;
    if (chartWidth <= 0) return;

    final touchX = (pos.dx - paddingLeft).clamp(0.0, chartWidth);
    final ratio = touchX / chartWidth;
    final idx = (ratio * (points.length - 1)).round().clamp(
      0,
      points.length - 1,
    );

    setState(() {
      _selectedIndex = idx;
    });
  }
}

class _ZoneLegendItem extends StatelessWidget {
  const _ZoneLegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// CustomPainter that renders pH trend curve, reference freshness bands, and point selection
class _TelemetryChartPainter extends CustomPainter {
  _TelemetryChartPainter({required this.readings, required this.selectedIndex});

  final List<Telemetry> readings;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.isEmpty) return;

    const paddingLeft = 36.0;
    const paddingRight = 16.0;
    const paddingTop = 12.0;
    const paddingBottom = 24.0;

    final drawWidth = size.width - paddingLeft - paddingRight;
    final drawHeight = size.height - paddingTop - paddingBottom;

    if (drawWidth <= 0 || drawHeight <= 0) return;

    // Determine min/max pH range for scaling (with bounds 4.0 to 10.0 minimum range)
    double minPh = 4.0;
    double maxPh = 10.0;
    for (final r in readings) {
      if (r.ph < minPh) minPh = (r.ph - 0.5).clamp(0.0, 14.0);
      if (r.ph > maxPh) maxPh = (r.ph + 0.5).clamp(0.0, 14.0);
    }
    final phRange = maxPh - minPh;

    double yForPh(double ph) {
      final norm = (ph - minPh) / phRange;
      return paddingTop + drawHeight * (1.0 - norm.clamp(0.0, 1.0));
    }

    double xForIndex(int index) {
      if (readings.length <= 1) return paddingLeft + drawWidth / 2;
      return paddingLeft + (index / (readings.length - 1)) * drawWidth;
    }

    // 1. Draw Freshness Threshold Reference Background Bands
    final freshY = yForPh(6.5);
    final moderateY = yForPh(7.2);

    // Fresh Zone (< 6.5)
    final freshRect = Rect.fromLTRB(
      paddingLeft,
      freshY,
      size.width - paddingRight,
      paddingTop + drawHeight,
    );
    canvas.drawRect(
      freshRect,
      Paint()..color = AppColors.fresh.withValues(alpha: 0.06),
    );

    // Moderate Zone (6.5 - 7.2)
    final modRect = Rect.fromLTRB(
      paddingLeft,
      moderateY,
      size.width - paddingRight,
      freshY.clamp(paddingTop, paddingTop + drawHeight),
    );
    canvas.drawRect(
      modRect,
      Paint()..color = AppColors.moderate.withValues(alpha: 0.06),
    );

    // Spoiled Zone (>= 7.2)
    final spoiledRect = Rect.fromLTRB(
      paddingLeft,
      paddingTop,
      size.width - paddingRight,
      moderateY.clamp(paddingTop, paddingTop + drawHeight),
    );
    canvas.drawRect(
      spoiledRect,
      Paint()..color = AppColors.spoiled.withValues(alpha: 0.06),
    );

    // 2. Draw Horizontal Threshold Grid Lines
    final linePaint = Paint()
      ..color = AppColors.line.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dashPaint = Paint()
      ..color = AppColors.muted.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Grid lines for 6.5 and 7.2 pH thresholds
    for (final threshold in [6.5, 7.2]) {
      final y = yForPh(threshold);
      if (y >= paddingTop && y <= paddingTop + drawHeight) {
        canvas.drawLine(
          Offset(paddingLeft, y),
          Offset(size.width - paddingRight, y),
          dashPaint,
        );
      }
    }

    // Border line
    canvas.drawRect(
      Rect.fromLTRB(
        paddingLeft,
        paddingTop,
        size.width - paddingRight,
        paddingTop + drawHeight,
      ),
      linePaint,
    );

    // 3. Draw Y-Axis pH Labels
    const textStyle = TextStyle(
      color: AppColors.muted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    for (final phVal in [minPh, 6.5, 7.2, maxPh]) {
      final y = yForPh(phVal);
      if (y >= paddingTop && y <= paddingTop + drawHeight) {
        final tp = TextPainter(
          text: TextSpan(text: phVal.toStringAsFixed(1), style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(paddingLeft - tp.width - 6, y - tp.height / 2));
      }
    }

    // 4. Construct Curve Path and Gradient Fill
    final path = Path();
    final fillPath = Path();

    final points = <Offset>[];
    for (var i = 0; i < readings.length; i++) {
      points.add(Offset(xForIndex(i), yForPh(readings[i].ph)));
    }

    if (points.isNotEmpty) {
      path.moveTo(points.first.dx, points.first.dy);
      fillPath.moveTo(points.first.dx, paddingTop + drawHeight);
      fillPath.lineTo(points.first.dx, points.first.dy);

      for (var i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final controlX = (p0.dx + p1.dx) / 2;
        path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
        fillPath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
      }

      fillPath.lineTo(points.last.dx, paddingTop + drawHeight);
      fillPath.close();

      // Area gradient fill
      final fillGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.teal.withValues(alpha: 0.25),
          AppColors.teal.withValues(alpha: 0.02),
        ],
      );

      final fillPaint = Paint()
        ..shader = fillGradient.createShader(
          Rect.fromLTRB(
            paddingLeft,
            paddingTop,
            size.width - paddingRight,
            paddingTop + drawHeight,
          ),
        );
      canvas.drawPath(fillPath, fillPaint);

      // Line path paint
      final pathPaint = Paint()
        ..color = AppColors.teal
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(path, pathPaint);

      // 5. Draw Data Points & Highlights
      for (var i = 0; i < points.length; i++) {
        final pt = points[i];
        final isSelected = i == selectedIndex;
        final statusColor = switch (readings[i].status) {
          FishStatus.fresh => AppColors.fresh,
          FishStatus.moderate => AppColors.moderate,
          FishStatus.spoiled => AppColors.spoiled,
        };

        if (isSelected) {
          // Vertical indicator line
          canvas.drawLine(
            Offset(pt.dx, paddingTop),
            Offset(pt.dx, paddingTop + drawHeight),
            Paint()
              ..color = statusColor.withValues(alpha: 0.4)
              ..strokeWidth = 1.5,
          );

          // Outer halo ring
          canvas.drawCircle(
            pt,
            8.0,
            Paint()..color = statusColor.withValues(alpha: 0.25),
          );
          canvas.drawCircle(pt, 5.0, Paint()..color = Colors.white);
          canvas.drawCircle(pt, 3.5, Paint()..color = statusColor);
        } else {
          canvas.drawCircle(pt, 3.0, Paint()..color = statusColor);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TelemetryChartPainter oldDelegate) {
    return oldDelegate.readings != readings ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
