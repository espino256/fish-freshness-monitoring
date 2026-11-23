import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/telemetry.dart';
import 'inspection_card.dart';

/// Independent sensor feed. It never becomes an image result or writes data.
class LivePhCard extends StatefulWidget {
  const LivePhCard({
    super.key,
    this.readings,
    this.unavailableReason,
    this.onRefresh,
    this.simulated = false,
    this.snapshot,
  });
  final Stream<List<Telemetry>>? readings;
  final AsyncSnapshot<List<Telemetry>>? snapshot;
  final String? unavailableReason;
  final VoidCallback? onRefresh;
  final bool simulated;

  @override
  State<LivePhCard> createState() => _LivePhCardState();
}

class _LivePhCardState extends State<LivePhCard>
    with AutomaticKeepAliveClientMixin<LivePhCard> {
  Timer? _clock;
  String? _selectedId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(LivePhCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A changed account/access state must not carry a device selection over.
    if (oldWidget.unavailableReason != widget.unavailableReason) {
      _selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.unavailableReason != null) {
      return _card(const AsyncSnapshot.nothing());
    }
    if (widget.snapshot case final snapshot?) return _card(snapshot);
    if (widget.readings == null) return _card(const AsyncSnapshot.nothing());
    return StreamBuilder<List<Telemetry>>(
      stream: widget.readings,
      builder: (_, snapshot) => _card(snapshot),
    );
  }

  Widget _card(AsyncSnapshot<List<Telemetry>> snapshot) {
    final raw = snapshot.data ?? const <Telemetry>[];
    final rows = raw.where((r) => r.hasValidSensorValues).toList();
    // Deduplicate by Firebase record ID to keep selection values unambiguous.
    final devices = {for (final r in rows) r.id: r};
    final selected =
        devices[_selectedId] ??
        (_selectedId == null && devices.length == 1
            ? devices.values.single
            : null);
    final blocked = widget.unavailableReason != null;
    final waiting =
        !snapshot.hasData &&
        snapshot.connectionState == ConnectionState.waiting;
    final stale =
        selected != null &&
        !widget.simulated &&
        selected.isStale(DateTime.now().toUtc());
    final usable = !blocked && !snapshot.hasError && selected != null;
    final status = blocked
        ? 'ACCESS REQUIRED'
        : snapshot.hasError
        ? 'UNAVAILABLE'
        : waiting
        ? 'CONNECTING'
        : !usable
        ? 'NO READING'
        : widget.simulated
        ? 'SIMULATED'
        : stale
        ? 'STALE'
        : 'LIVE';
    final color = usable && !stale ? AppColors.teal : AppColors.muted;
    final explanation =
        widget.unavailableReason ??
        (snapshot.hasError
            ? snapshot.error is FormatException
                  ? 'Unable to read telemetry. The sensor record format is invalid; check pH, ADC, voltage and timestamp fields.'
                  : 'Unable to read telemetry. Check your network, verified email and database access, then refresh.'
            : waiting
            ? 'Connecting to your ESP32 pH feed…'
            : raw.isNotEmpty && rows.isEmpty
            ? 'The received sensor data is invalid. Check the pH, ADC, voltage and timestamp fields.'
            : devices.isEmpty
            ? (widget.readings == null && widget.snapshot == null
                  ? 'No sensor stream is connected. Connect the calibrated ESP32 pH device to see a reading.'
                  : 'No telemetry yet. Calibrate and connect the pH device.')
            : selected == null
            ? (_selectedId == null
                  ? 'Choose a sensor device to display its pH reading.'
                  : 'The selected sensor is no longer publishing. Choose an available device.')
            : stale
            ? 'Last received value. The sensor feed is stale; check device power and Wi-Fi.'
            : 'Reading received from the selected pH sensor.');
    return InspectionCard(
      key: const Key('live-ph-card'),
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InspectionHeading(
            icon: Icons.water_drop_outlined,
            title: 'Sensor pH',
            subtitle: 'Independent ESP32 reading',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                usable ? 'pH ${selected.ph.toStringAsFixed(2)}' : 'pH N/A',
                key: const Key('sensor-ph-value'),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -1,
                ),
              ),
              InspectionBadge(
                label: status,
                color: color,
                key: const Key('sensor-ph-status'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            explanation,
            key: const Key('sensor-ph-message'),
            style: const TextStyle(height: 1.5),
          ),
          if (!blocked &&
              !snapshot.hasError &&
              (devices.length > 1 ||
                  _selectedId != null &&
                      !devices.containsKey(_selectedId) &&
                      devices.isNotEmpty)) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'ph-device-${devices.containsKey(_selectedId) ? _selectedId : 'none'}',
              ),
              initialValue: devices.containsKey(_selectedId)
                  ? _selectedId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sensor device'),
              items: [
                for (final reading in devices.values)
                  DropdownMenuItem(
                    value: reading.id,
                    child: Text(
                      '${reading.deviceId} (${reading.id})',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => setState(() => _selectedId = id),
            ),
          ],
          if (usable) ...[
            const SizedBox(height: 16),
            Text(
              'Device: ${selected.deviceId}',
              key: const Key('sensor-ph-device'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Updated ${selected.timestamp.toLocal().toString().substring(0, 19)}',
              key: const Key('sensor-ph-timestamp'),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                InspectionBadge(
                  label: 'ADC ${selected.adcRaw.toStringAsFixed(1)} / 4095',
                ),
                InspectionBadge(
                  label:
                      'Measured ${selected.measuredVoltage.toStringAsFixed(3)} V',
                ),
                InspectionBadge(
                  label:
                      'Nominal ${selected.nominalVoltage.toStringAsFixed(3)} V',
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Sensor pH is not estimated from the image and is not automatically linked to this fish or session.',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
          ),
          if (widget.onRefresh != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh sensor feed'),
            ),
          ],
        ],
      ),
    );
  }
}
