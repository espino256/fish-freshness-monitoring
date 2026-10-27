import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/app_theme.dart';
import '../models/classification.dart';
import '../models/fish_sample.dart';
import '../services/firebase_service.dart';
import '../services/image_analysis_service.dart';
import '../services/report_service.dart';
import '../widgets/neumorphic_card.dart';
import '../widgets/ocean_art.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1380),
        child: child,
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.samples,
    required this.thresholds,
    required this.onNavigate,
    required this.onAddSample,
    super.key,
  });

  final List<FishSample> samples;
  final FreshnessThresholds thresholds;
  final ValueChanged<int> onNavigate;
  final VoidCallback onAddSample;

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OceanArt(),
        const SizedBox(height: 23),
        SectionHeading(
          'Monitoring overview',
          subtitle:
              'Fish Freshness Monitoring System · '
              'Sensor observations and visual analysis remain separate.',
          action: FilledButton.icon(
            onPressed: onAddSample,
            icon: const Icon(Icons.add),
            label: const Text('New sample'),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          children: [
            StatusPill(
              label: FirebaseService.isReady
                  ? 'FIREBASE CONNECTED'
                  : 'LOCAL WORKSPACE',
              color: FirebaseService.isReady
                  ? AppColors.fresh
                  : AppColors.moderate,
              icon: FirebaseService.isReady
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!FirebaseService.isReady)
          _UnavailableCard(
            title: 'No data · sensor readings unavailable',
            detail:
                'Connect Firebase to view live pH values. AquaSense never '
                'fills this panel with simulated readings.',
            icon: Icons.sensors_off_rounded,
            actionLabel: 'Open settings',
            onPressed: () => onNavigate(7),
          )
        else
          StreamBuilder<List<SensorReading>>(
            stream: FirebaseService.watchReadings(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _UnavailableCard(
                  title: 'Could not load sensor data',
                  detail: '${snapshot.error}',
                  icon: Icons.error_outline,
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const NeumorphicCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              }
              final readings = snapshot.data ?? [];
              if (readings.isEmpty) {
                return const _UnavailableCard(
                  title: 'Waiting for the first device reading',
                  detail:
                      'Firebase is configured, but no pH readings have been '
                      'received. Confirm the ESP32 publishing workflow.',
                  icon: Icons.sensors_off_rounded,
                );
              }
              return _DashboardSensorData(
                readings: readings,
                thresholds: thresholds,
              );
            },
          ),
        if (FirebaseService.isReady) ...[
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: const _LatestVisualSummary(),
                  ),
                  SizedBox(width: cardWidth, child: const _DeviceSummary()),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: wide ? 6 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeading(
                          'Recent sample records',
                          subtitle: 'Stored in this workspace',
                        ),
                        const SizedBox(height: 14),
                        if (samples.isEmpty)
                          const _EmptyInline(
                            icon: Icons.science_outlined,
                            message:
                                'No samples recorded. Add a sample before '
                                'linking readings or image observations.',
                          )
                        else
                          for (final sample in samples.take(4))
                            _SampleRow(sample: sample),
                        if (samples.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => onNavigate(3),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('View all samples'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: wide ? 18 : 0, height: wide ? 0 : 16),
                Flexible(
                  flex: wide ? 4 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Research note',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 9),
                        const Text(
                          'Freshness bands are initial research parameters, '
                          'not universal safety guarantees. pH and image hue '
                          'are shown independently.',
                          style: TextStyle(color: AppColors.muted, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => onNavigate(2),
                          icon: const Icon(Icons.image_search_rounded),
                          label: const Text('Analyze an image'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _DashboardSensorData extends StatelessWidget {
  const _DashboardSensorData({
    required this.readings,
    required this.thresholds,
  });

  final List<SensorReading> readings;
  final FreshnessThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final latest = readings.first;
    final classification = thresholds.classifyPh(latest.ph);
    final age = DateTime.now().toUtc().difference(latest.timestamp);
    final status = age > const Duration(minutes: 1)
        ? 'Stale data'
        : 'Recent data';
    final statusColor = age > const Duration(minutes: 1)
        ? AppColors.moderate
        : AppColors.fresh;
    final latestBySample = <String, SensorReading>{};
    for (final reading in readings) {
      final sampleId = reading.sampleId;
      if (sampleId != null) {
        latestBySample.putIfAbsent(sampleId, () => reading);
      }
    }
    final counts = <FreshnessClass, int>{
      for (final category in FreshnessClass.values) category: 0,
    };
    for (final reading in latestBySample.values) {
      final category = thresholds.classifyPh(reading.ph);
      if (category != null) counts[category] = counts[category]! + 1;
    }
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850 ? 3 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  width: width,
                  label: 'Latest pH',
                  value: latest.ph.toStringAsFixed(2),
                  detail: 'Sample ${latest.sampleId ?? 'not linked'}',
                  icon: Icons.water_drop_outlined,
                  color: AppColors.teal,
                ),
                _MetricCard(
                  width: width,
                  label: 'pH classification',
                  value: classification?.label ?? 'Unavailable',
                  detail: 'Research threshold band',
                  icon: Icons.science_outlined,
                  color: _classColor(classification),
                ),
                _MetricCard(
                  width: width,
                  label: 'Last update',
                  value: _shortDate(latest.timestamp.toLocal()),
                  detail: status,
                  icon: Icons.schedule_rounded,
                  color: statusColor,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: wide ? 7 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'pH trend',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 180,
                          child: ReadingChart(readings: readings),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Showing ${readings.length} latest stored readings',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: wide ? 14 : 0, height: wide ? 0 : 12),
                Flexible(
                  flex: wide ? 3 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Linked sample counts',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final category in [
                          FreshnessClass.fresh,
                          FreshnessClass.moderate,
                          FreshnessClass.spoiled,
                          FreshnessClass.review,
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 9,
                                  color: _classColor(category),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(category.label)),
                                Text(
                                  '${counts[category] ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LatestVisualSummary extends StatelessWidget {
  const _LatestVisualSummary();

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<VisualAnalysisRecord>>(
    stream: FirebaseService.watchAnalyses(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _UnavailableCard(
          title: 'Image analysis unavailable',
          detail: '${snapshot.error}',
          icon: Icons.error_outline,
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingCard(message: 'Loading image analysis…');
      }
      final records = snapshot.data ?? [];
      if (records.isEmpty) {
        return const _UnavailableCard(
          title: 'No visual result stored',
          detail:
              'Select and analyze a fish image to create a visual observation.',
          icon: Icons.image_search_outlined,
        );
      }
      final latest = records.first;
      final color = switch (latest.classification) {
        'Fresh' => AppColors.fresh,
        'Moderate' => AppColors.moderate,
        'Spoiled' => AppColors.spoiled,
        _ => AppColors.muted,
      };
      return NeumorphicCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest visual analysis',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            StatusPill(
              label: latest.classification,
              color: color,
              icon: Icons.image_search_outlined,
            ),
            const SizedBox(height: 9),
            Text(
              'Mean hue ${latest.meanHue.toStringAsFixed(2)}° · '
              'Sample ${latest.sampleId}',
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Recorded ${latest.timestamp.toLocal()}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      );
    },
  );
}

class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<DeviceStatus>>(
    stream: FirebaseService.watchDevices(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _UnavailableCard(
          title: 'Device status unavailable',
          detail: '${snapshot.error}',
          icon: Icons.error_outline,
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingCard(message: 'Loading device status…');
      }
      final statuses = {
        for (final device in snapshot.data ?? <DeviceStatus>[])
          device.id: device,
      };
      return NeumorphicCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device status',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            _dashboardDeviceRow('ESP32 pH sensor', statuses['esp32-ph']),
            _dashboardDeviceRow('ESP32-CAM', statuses['esp32-cam']),
          ],
        ),
      );
    },
  );
}

Widget _dashboardDeviceRow(String label, DeviceStatus? device) {
  final lastSeen = device?.lastSeen;
  final fresh =
      lastSeen != null &&
      DateTime.now().toUtc().difference(lastSeen) < const Duration(minutes: 1);
  final online = fresh && (device?.online ?? false);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(
          online ? Icons.check_circle : Icons.circle_outlined,
          color: online ? AppColors.fresh : AppColors.moderate,
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          device == null
              ? 'No heartbeat'
              : online
              ? 'Online'
              : 'Offline / stale',
          style: TextStyle(
            color: online ? AppColors.fresh : AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class LiveMonitoringPage extends StatefulWidget {
  const LiveMonitoringPage({required this.thresholds, super.key});

  final FreshnessThresholds thresholds;

  @override
  State<LiveMonitoringPage> createState() => _LiveMonitoringPageState();
}

class _LiveMonitoringPageState extends State<LiveMonitoringPage> {
  late Stream<List<SensorReading>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _makeStream();
  }

  Stream<List<SensorReading>> _makeStream() => FirebaseService.isReady
      ? FirebaseService.watchReadings()
      : const Stream.empty();

  void _refresh() => setState(() => _stream = _makeStream());

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          'Live pH monitoring',
          subtitle: 'Live device readings only; no synthetic values are shown.',
        ),
        const SizedBox(height: 18),
        if (!FirebaseService.isReady)
          const _UnavailableCard(
            title: 'Firebase is not connected',
            detail:
                'Configure Firebase and publish readings from the ESP32 to '
                'see live data here.',
            icon: Icons.sensors_off_rounded,
          )
        else
          StreamBuilder<List<SensorReading>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _UnavailableCard(
                  title: 'Reading stream error',
                  detail: '${snapshot.error}',
                  icon: Icons.error_outline,
                  actionLabel: 'Reconnect',
                  onPressed: _refresh,
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingCard(message: 'Connecting to readings…');
              }
              final readings = snapshot.data ?? [];
              if (readings.isEmpty) {
                return _UnavailableCard(
                  title: 'No readings received',
                  detail:
                      'The database has no pH readings yet. Check the device '
                      'connection and publishing interval.',
                  icon: Icons.sensors_off_rounded,
                  actionLabel: 'Refresh',
                  onPressed: _refresh,
                );
              }
              final latest = readings.first;
              final classification = widget.thresholds.classifyPh(latest.ph);
              final stale =
                  DateTime.now().toUtc().difference(latest.timestamp) >
                  const Duration(minutes: 1);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 700;
                      return Flex(
                        direction: wide ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            flex: wide ? 5 : 0,
                            fit: wide ? FlexFit.tight : FlexFit.loose,
                            child: NeumorphicCard(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'LATEST READING',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 11,
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      StatusPill(
                                        label: stale ? 'STALE' : 'RECENT',
                                        color: stale
                                            ? AppColors.moderate
                                            : AppColors.fresh,
                                        icon: stale
                                            ? Icons.schedule
                                            : Icons.check_circle_outline,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    latest.ph.toStringAsFixed(2),
                                    style: const TextStyle(
                                      color: AppColors.navy,
                                      fontSize: 58,
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    classification?.label ??
                                        'Classification unavailable',
                                    style: TextStyle(
                                      color: _classColor(classification),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Recorded ${latest.timestamp.toLocal()}',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Sample ${latest.sampleId ?? 'not associated'}'
                                    ' · Device ${latest.deviceId ?? 'not reported'}',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _PhThresholdScale(
                                    value: latest.ph,
                                    thresholds: widget.thresholds,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: wide ? 14 : 0, height: wide ? 0 : 14),
                          Flexible(
                            flex: wide ? 7 : 0,
                            fit: wide ? FlexFit.tight : FlexFit.loose,
                            child: NeumorphicCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reading trend',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 220,
                                    child: ReadingChart(readings: readings),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Recent readings',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Reconnect to reading stream',
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        for (final reading in readings.take(10))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.water_drop_outlined,
                              color: AppColors.teal,
                            ),
                            title: Text(
                              'pH ${reading.ph.toStringAsFixed(2)} · '
                              '${widget.thresholds.classifyPh(reading.ph)?.label ?? 'Review'}',
                            ),
                            subtitle: Text(
                              '${reading.timestamp.toLocal()} · '
                              'Sample ${reading.sampleId ?? 'not linked'}',
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Thresholds are screening parameters, not a food-safety '
                      'determination.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class VisualAnalysisPage extends StatefulWidget {
  const VisualAnalysisPage({
    required this.samples,
    required this.user,
    required this.thresholds,
    super.key,
  });

  final List<FishSample> samples;
  final User? user;
  final FreshnessThresholds thresholds;

  @override
  State<VisualAnalysisPage> createState() => _VisualAnalysisPageState();
}

class _VisualAnalysisPageState extends State<VisualAnalysisPage> {
  final _picker = ImagePicker();
  final _service = const ImageAnalysisService();
  XFile? _image;
  Uint8List? _bytes;
  HueAnalysis? _result;
  String? _selectedSampleId;
  String? _error;
  bool _processing = false;
  bool _uploading = false;
  String? _savedPath;
  String? _sourceStoragePath;
  String? _loadingCameraUploadId;
  Stream<List<DeviceImageUpload>>? _cameraUploadsStream;

  @override
  void initState() {
    super.initState();
    _setCameraUploadsStream();
  }

  @override
  void didUpdateWidget(covariant VisualAnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.uid != widget.user?.uid) _setCameraUploadsStream();
  }

  void _setCameraUploadsStream() {
    _cameraUploadsStream = widget.user != null && FirebaseService.isReady
        ? FirebaseService.watchDeviceUploads()
        : null;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 92);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = image;
        _bytes = bytes;
        _result = null;
        _savedPath = null;
        _sourceStoragePath = null;
        _error = null;
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Could not open image: $error');
    }
  }

  Future<void> _loadCameraUpload(DeviceImageUpload upload) async {
    if (!widget.samples.any((sample) => sample.id == upload.sampleId)) {
      setState(
        () => _error =
            'Camera image references sample ${upload.sampleId}, which is not '
            'available in this workspace.',
      );
      return;
    }
    setState(() {
      _loadingCameraUploadId = upload.id;
      _error = null;
    });
    try {
      final bytes = await FirebaseService.downloadImage(upload.storagePath);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('The camera image is empty or no longer available.');
      }
      if (!mounted) return;
      setState(() {
        _image = null;
        _bytes = bytes;
        _result = null;
        _savedPath = null;
        _sourceStoragePath = upload.storagePath;
        _selectedSampleId = upload.sampleId;
        _loadingCameraUploadId = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not download the camera image: $error';
        _loadingCameraUploadId = null;
      });
    }
  }

  Future<void> _analyze() async {
    final bytes = _bytes;
    if (bytes == null) {
      setState(() => _error = 'Select an image before analysis.');
      return;
    }
    if (_selectedSampleId == null) {
      setState(() => _error = 'Create or select a sample to link this image.');
      return;
    }
    setState(() {
      _processing = true;
      _error = null;
      _result = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      final result = _service.analyze(bytes);
      if (!mounted) return;
      setState(() {
        _result = result;
        _processing = false;
      });
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
        _processing = false;
      });
    }
  }

  Future<void> _upload() async {
    final result = _result;
    final image = _image;
    final bytes = _bytes;
    final sampleId = _selectedSampleId;
    final sourceStoragePath = _sourceStoragePath;
    if (result == null ||
        bytes == null ||
        sampleId == null ||
        (sourceStoragePath == null && image == null)) {
      setState(() => _error = 'Analyze a linked image before saving.');
      return;
    }
    if (widget.user == null || !FirebaseService.isReady) {
      setState(() {
        _error =
            'Sign in to a configured Firebase project before uploading. '
            'The result is not saved to cloud storage.';
      });
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final classification =
          widget.thresholds.classifyHue(result.meanHue)?.label ??
          'Review required';
      final String savedPath;
      if (sourceStoragePath != null) {
        await FirebaseService.saveAnalysisReference(
          sampleId: sampleId,
          storagePath: sourceStoragePath,
          meanHue: result.meanHue,
          classification: classification,
        );
        savedPath = sourceStoragePath;
      } else {
        savedPath = await FirebaseService.uploadAnalysis(
          sampleId: sampleId,
          imageBytes: bytes,
          fileName: image!.name,
          meanHue: result.meanHue,
          classification: classification,
        );
      }
      if (!mounted) return;
      setState(() {
        _savedPath = savedPath;
        _uploading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Upload failed; the analysis was not saved: $error';
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          'Visual freshness analysis',
          subtitle:
              'Mean HSV hue from a centered 200 × 200 pixel region of interest.',
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: wide ? 6 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        if (_bytes == null)
                          Container(
                            height: 320,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SvgPicture.asset(
                                  'assets/images/gill_lab.svg',
                                  fit: BoxFit.cover,
                                  semanticsLabel:
                                      'Original illustrative fish gill image',
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0x660A202C),
                                  ),
                                ),
                                const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 50,
                                      color: AppColors.aqua,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Select a clear gill-cover image',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Originals are not uploaded automatically.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        else
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _bytes!,
                              height: 320,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(
                                    height: 320,
                                    child: Center(
                                      child: Text('Image preview unavailable.'),
                                    ),
                                  ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _processing || _uploading
                                  ? null
                                  : () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Choose image'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _processing || _uploading
                                  ? null
                                  : () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _cameraUploadsSection(),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 16),
                Flexible(
                  flex: wide ? 5 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sample association',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (widget.samples.isEmpty)
                          const Text(
                            'Create a sample before analyzing an image.',
                            style: TextStyle(color: AppColors.muted),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSampleId,
                            decoration: const InputDecoration(
                              labelText: 'Sample ID',
                            ),
                            items: [
                              for (final sample in widget.samples)
                                DropdownMenuItem(
                                  value: sample.id,
                                  child: Text(
                                    '${sample.id} · ${sample.fishType}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _selectedSampleId = value),
                          ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed:
                              _processing ||
                                  widget.samples.isEmpty ||
                                  _bytes == null
                              ? null
                              : _analyze,
                          icon: _processing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(
                            _processing ? 'Analyzing…' : 'Analyze ROI',
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_result != null)
                          _AnalysisResult(
                            result: _result!,
                            sampleId: _selectedSampleId!,
                            thresholds: widget.thresholds,
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.spoiled,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (_result != null) ...[
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            onPressed: _uploading ? null : _upload,
                            icon: _uploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_outlined),
                            label: Text(
                              _savedPath == null
                                  ? _sourceStoragePath == null
                                        ? 'Save image and result to Firebase'
                                        : 'Save result to Firebase'
                                  : 'Saved to Firebase',
                            ),
                          ),
                          if (_savedPath != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SelectableText(
                                _savedPath!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 15),
                        const Text(
                          'The ROI is the geometric image center. Position '
                          'the gill cover in the center before analysis. '
                          'Lighting, white balance, and sample preparation '
                          'affect hue; this is not a safety determination.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _cameraUploadsSection() {
    if (_cameraUploadsStream == null) {
      return const _CameraUploadPanel(
        child: Text(
          'Sign in to a configured Firebase project to load camera uploads.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      );
    }
    return _CameraUploadPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ESP32-CAM uploads',
            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<DeviceImageUpload>>(
            stream: _cameraUploadsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load camera uploads: ${snapshot.error}',
                  style: const TextStyle(
                    color: AppColors.spoiled,
                    fontSize: 12,
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final uploads = snapshot.data ?? const <DeviceImageUpload>[];
              if (uploads.isEmpty) {
                return const Text(
                  'No camera images have been uploaded yet.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                );
              }
              return Column(
                children: [
                  for (final upload in uploads)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.photo_camera_back_outlined,
                            color: AppColors.teal,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${upload.sampleId} · '
                              '${upload.timestamp.toLocal().toString().substring(0, 16)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed:
                                _loadingCameraUploadId == null &&
                                    !_processing &&
                                    !_uploading
                                ? () => _loadCameraUpload(upload)
                                : null,
                            child: _loadingCameraUploadId == upload.id
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Use image'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CameraUploadPanel extends StatelessWidget {
  const _CameraUploadPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.teal.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: child,
  );
}

class _AnalysisResult extends StatelessWidget {
  const _AnalysisResult({
    required this.result,
    required this.sampleId,
    required this.thresholds,
  });

  final HueAnalysis result;
  final String sampleId;
  final FreshnessThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final category = thresholds.classifyHue(result.meanHue);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mean hue ${result.meanHue.toStringAsFixed(2)}°',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 6),
          StatusPill(
            label: category?.label ?? 'Review required',
            color: _classColor(category),
          ),
          const SizedBox(height: 7),
          Text(
            'Sample $sampleId · ROI ${ImageAnalysisService.roiSize} × '
            '${ImageAnalysisService.roiSize} at (${result.regionX}, '
            '${result.regionY}) from ${result.width} × ${result.height}',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class SamplesPage extends StatefulWidget {
  const SamplesPage({
    required this.samples,
    required this.thresholds,
    required this.onSave,
    required this.onError,
    super.key,
  });

  final List<FishSample> samples;
  final FreshnessThresholds thresholds;
  final Future<void> Function(List<FishSample>) onSave;
  final ValueChanged<String> onError;

  @override
  SamplesPageState createState() => SamplesPageState();
}

class SamplesPageState extends State<SamplesPage> {
  String _query = '';
  String _dateFilter = 'Any date';
  String _classFilter = 'All classifications';

  void openCreateForm() => _create();

  List<FishSample> get _filtered {
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();
    return widget.samples.where((sample) {
      final matchesText =
          query.isEmpty ||
          sample.id.toLowerCase().contains(query) ||
          sample.fishType.toLowerCase().contains(query);
      final matchesDate = switch (_dateFilter) {
        'Today' =>
          sample.collectedAt.year == now.year &&
              sample.collectedAt.month == now.month &&
              sample.collectedAt.day == now.day,
        'Last 7 days' =>
          now.difference(sample.collectedAt).inDays < 7 &&
              !sample.collectedAt.isAfter(now),
        _ => true,
      };
      return matchesText && matchesDate;
    }).toList()..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }

  Widget _sampleResults() {
    if (_classFilter == 'All classifications') {
      return _sampleList(_filtered);
    }
    if (!FirebaseService.isReady) {
      return const _UnavailableCard(
        title: 'Classification filter needs Firebase',
        detail:
            'Only stored sensor readings can drive this filter. Configure '
            'Firebase and link readings to sample IDs.',
        icon: Icons.cloud_off_outlined,
      );
    }
    return StreamBuilder<List<SensorReading>>(
      stream: FirebaseService.watchReadings(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _UnavailableCard(
            title: 'Could not load classifications',
            detail: '${snapshot.error}',
            icon: Icons.error_outline,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingCard(message: 'Loading linked readings…');
        }
        final latestBySample = <String, SensorReading>{};
        for (final reading in snapshot.data ?? <SensorReading>[]) {
          final sampleId = reading.sampleId;
          if (sampleId != null) {
            latestBySample.putIfAbsent(sampleId, () => reading);
          }
        }
        final filtered = _filtered.where((sample) {
          final reading = latestBySample[sample.id];
          if (reading == null) return false;
          return widget.thresholds.classifyPh(reading.ph)?.label ==
              _classFilter;
        }).toList();
        return _sampleList(
          filtered,
          emptyDetail:
              'No linked sensor readings match $_classFilter. Image-analysis '
              'results remain separate and are not used by this filter.',
        );
      },
    );
  }

  Widget _sampleList(List<FishSample> samples, {String? emptyDetail}) {
    if (samples.isEmpty) {
      return _UnavailableCard(
        title: widget.samples.isEmpty
            ? 'No samples yet'
            : 'No matching sample records',
        detail: widget.samples.isEmpty
            ? 'Add a sample to create its metadata record and unique ID.'
            : emptyDetail ?? 'Change the search text or filter and try again.',
        icon: Icons.science_outlined,
        actionLabel: widget.samples.isEmpty ? 'Add first sample' : null,
        onPressed: widget.samples.isEmpty ? _create : null,
      );
    }
    return NeumorphicCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      child: Column(
        children: [
          for (final sample in samples)
            _SampleRow(
              sample: sample,
              onTap: () => _showDetails(sample),
              onEdit: () => _edit(sample),
              onDelete: () => _delete(sample),
            ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final draft = await showDialog<FishSample>(
      context: context,
      builder: (context) => const _SampleFormDialog(),
    );
    if (draft == null) return;
    if (widget.samples.any((sample) => sample.id == draft.id)) {
      widget.onError('A sample with this ID already exists.');
      return;
    }
    await _persist([...widget.samples, draft]);
  }

  Future<void> _edit(FishSample sample) async {
    final draft = await showDialog<FishSample>(
      context: context,
      builder: (context) => _SampleFormDialog(sample: sample),
    );
    if (draft == null) return;
    await _persist([
      for (final current in widget.samples)
        if (current.id == sample.id) draft else current,
    ]);
  }

  void _showDetails(FishSample sample) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(sample.id),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine('Fish type', sample.fishType),
              _DetailLine('Details', sample.details),
              _DetailLine('Collected', sample.collectedAt.toLocal().toString()),
              _DetailLine(
                'Operator',
                sample.operatorName.isEmpty
                    ? 'Not specified'
                    : sample.operatorName,
              ),
              _DetailLine(
                'Remarks',
                sample.remarks.isEmpty ? 'None' : sample.remarks,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _edit(sample);
            },
            child: const Text('Edit metadata'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(FishSample sample) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sample?'),
        content: Text(
          'Delete ${sample.id} from this workspace? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _persist(
      widget.samples.where((item) => item.id != sample.id).toList(),
    );
  }

  Future<void> _persist(List<FishSample> samples) async {
    try {
      await widget.onSave(samples);
    } on Object catch (error) {
      widget.onError('$error');
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Sample management',
          subtitle:
              'Sample metadata is saved locally; cloud sync requires sign-in.',
          action: FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Add sample'),
          ),
        ),
        const SizedBox(height: 16),
        NeumorphicCard(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 620;
              final search = TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search sample ID or fish type',
                ),
                onChanged: (value) => setState(() => _query = value),
              );
              final date = DropdownButtonFormField<String>(
                initialValue: _dateFilter,
                decoration: const InputDecoration(labelText: 'Collection date'),
                items: const [
                  DropdownMenuItem(value: 'Any date', child: Text('Any date')),
                  DropdownMenuItem(value: 'Today', child: Text('Today')),
                  DropdownMenuItem(
                    value: 'Last 7 days',
                    child: Text('Last 7 days'),
                  ),
                ],
                onChanged: (value) => setState(() => _dateFilter = value!),
              );
              final freshness = DropdownButtonFormField<String>(
                initialValue: _classFilter,
                decoration: const InputDecoration(
                  labelText: 'Freshness classification',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'All classifications',
                    child: Text('All classifications'),
                  ),
                  DropdownMenuItem(value: 'Fresh', child: Text('Fresh')),
                  DropdownMenuItem(value: 'Moderate', child: Text('Moderate')),
                  DropdownMenuItem(value: 'Spoiled', child: Text('Spoiled')),
                ],
                onChanged: (value) => setState(() => _classFilter = value!),
              );
              return Flex(
                direction: stacked ? Axis.vertical : Axis.horizontal,
                children: [
                  Flexible(
                    flex: stacked ? 0 : 4,
                    fit: stacked ? FlexFit.loose : FlexFit.tight,
                    child: search,
                  ),
                  SizedBox(width: stacked ? 0 : 10, height: stacked ? 10 : 0),
                  Flexible(
                    flex: stacked ? 0 : 2,
                    fit: stacked ? FlexFit.loose : FlexFit.tight,
                    child: date,
                  ),
                  SizedBox(width: stacked ? 0 : 10, height: stacked ? 10 : 0),
                  Flexible(
                    flex: stacked ? 0 : 2,
                    fit: stacked ? FlexFit.loose : FlexFit.tight,
                    child: freshness,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _sampleResults(),
      ],
    ),
  );
}

class _SampleFormDialog extends StatefulWidget {
  const _SampleFormDialog({this.sample});

  final FishSample? sample;

  @override
  State<_SampleFormDialog> createState() => _SampleFormDialogState();
}

class _SampleFormDialogState extends State<_SampleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fishType;
  late final TextEditingController _details;
  late final TextEditingController _operator;
  late final TextEditingController _remarks;
  late DateTime _collectedAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final sample = widget.sample;
    _fishType = TextEditingController(text: sample?.fishType ?? '');
    _details = TextEditingController(text: sample?.details ?? '');
    _operator = TextEditingController(text: sample?.operatorName ?? '');
    _remarks = TextEditingController(text: sample?.remarks ?? '');
    _collectedAt = sample?.collectedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _fishType.dispose();
    _details.dispose();
    _operator.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _collectedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _collectedAt = DateTime(
        date.year,
        date.month,
        date.day,
        _collectedAt.hour,
        _collectedAt.minute,
      );
    });
  }

  Future<void> _chooseTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_collectedAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _collectedAt = DateTime(
        _collectedAt.year,
        _collectedAt.month,
        _collectedAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    Navigator.pop(
      context,
      FishSample(
        id: widget.sample?.id ?? FishSample.createId(now),
        fishType: _fishType.text.trim(),
        details: _details.text.trim(),
        collectedAt: _collectedAt,
        operatorName: _operator.text.trim(),
        remarks: _remarks.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.sample == null ? 'Create sample' : 'Edit sample'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.sample != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Sample ID: ${widget.sample!.id}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              TextFormField(
                controller: _fishType,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Fish type *'),
                maxLength: 120,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a fish type.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _details,
                decoration: const InputDecoration(
                  labelText: 'Sample details',
                  hintText: 'Collection site, preparation, etc.',
                ),
                maxLines: 2,
                maxLength: 2000,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Collected: ${_shortDate(_collectedAt)}',
                      style: const TextStyle(color: AppColors.ink),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _chooseDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Date'),
                      ),
                      TextButton.icon(
                        onPressed: _chooseTime,
                        icon: const Icon(Icons.schedule_outlined),
                        label: Text(
                          'Time · '
                          '${TimeOfDay.fromDateTime(_collectedAt).format(context)}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _operator,
                decoration: const InputDecoration(labelText: 'Operator'),
                maxLength: 160,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _remarks,
                decoration: const InputDecoration(labelText: 'Remarks'),
                maxLines: 2,
                maxLength: 4000,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: const Text('Save'),
      ),
    ],
  );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    required this.samples,
    required this.thresholds,
    super.key,
  });

  final List<FishSample> samples;
  final FreshnessThresholds thresholds;

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          'History & comparison',
          subtitle:
              'pH and image classifications are reported separately. '
              'Disagreement is flagged, not averaged.',
        ),
        const SizedBox(height: 18),
        if (!FirebaseService.isReady)
          const _UnavailableCard(
            title: 'Cloud history is unavailable',
            detail:
                'Firebase is not connected. Locally stored sample metadata '
                'remains available on the Samples and Reports screens.',
            icon: Icons.history_rounded,
          )
        else
          StreamBuilder<List<SensorReading>>(
            stream: FirebaseService.watchReadings(),
            builder: (context, readingSnapshot) {
              if (readingSnapshot.hasError) {
                return _UnavailableCard(
                  title: 'Could not load pH history',
                  detail: '${readingSnapshot.error}',
                  icon: Icons.error_outline,
                );
              }
              return StreamBuilder<List<VisualAnalysisRecord>>(
                stream: FirebaseService.watchAnalyses(),
                builder: (context, analysisSnapshot) {
                  if (analysisSnapshot.hasError) {
                    return _UnavailableCard(
                      title: 'Could not load image-analysis history',
                      detail: '${analysisSnapshot.error}',
                      icon: Icons.error_outline,
                    );
                  }
                  if (readingSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      analysisSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const _LoadingCard(
                      message: 'Loading stored research records…',
                    );
                  }
                  final readings = readingSnapshot.data ?? [];
                  final analyses = analysisSnapshot.data ?? [];
                  final latestBySample = <String, SensorReading>{};
                  for (final reading in readings) {
                    final sampleId = reading.sampleId;
                    if (sampleId != null &&
                        !latestBySample.containsKey(sampleId)) {
                      latestBySample[sampleId] = reading;
                    }
                  }
                  final analysesBySample = <String, VisualAnalysisRecord>{};
                  for (final analysis in analyses) {
                    analysesBySample.putIfAbsent(
                      analysis.sampleId,
                      () => analysis,
                    );
                  }
                  final sampleIds = {
                    ...latestBySample.keys,
                    ...analysesBySample.keys,
                  }.toList()..sort();
                  if (sampleIds.isEmpty) {
                    return const _UnavailableCard(
                      title: 'No linked observations yet',
                      detail:
                          'Readings and image analyses appear here when '
                          'they include the same sample ID.',
                      icon: Icons.compare_arrows_rounded,
                    );
                  }
                  return Column(
                    children: [
                      for (final id in sampleIds)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _HistorySampleCard(
                            sampleId: id,
                            sample: samples
                                .where((sample) => sample.id == id)
                                .firstOrNull,
                            reading: latestBySample[id],
                            analysis: analysesBySample[id],
                            thresholds: thresholds,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
      ],
    ),
  );
}

class _HistorySampleCard extends StatelessWidget {
  const _HistorySampleCard({
    required this.sampleId,
    required this.sample,
    required this.reading,
    required this.analysis,
    required this.thresholds,
  });

  final String sampleId;
  final FishSample? sample;
  final SensorReading? reading;
  final VisualAnalysisRecord? analysis;
  final FreshnessThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final phClass = reading == null ? null : thresholds.classifyPh(reading!.ph);
    final hueClass = analysis == null
        ? null
        : thresholds.classifyHue(analysis!.meanHue);
    final conflict =
        phClass != null &&
        hueClass != null &&
        phClass != FreshnessClass.review &&
        hueClass != FreshnessClass.review &&
        phClass != hueClass;
    return NeumorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sample == null
                      ? sampleId
                      : '${sample!.id} · ${sample!.fishType}',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (conflict)
                const StatusPill(
                  label: 'RESULTS CONFLICT',
                  color: AppColors.spoiled,
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _Observation(
                title: 'pH reading',
                value: reading == null
                    ? 'No linked pH data'
                    : '${reading!.ph.toStringAsFixed(2)} · '
                          '${phClass?.label ?? 'Unclassified'}',
                timestamp: reading?.timestamp,
                color: _classColor(phClass),
              ),
              _Observation(
                title: 'Visual mean hue',
                value: analysis == null
                    ? 'No image analysis'
                    : '${analysis!.meanHue.toStringAsFixed(2)}° · '
                          '${hueClass?.label ?? 'Unclassified'}',
                timestamp: analysis?.timestamp,
                color: _classColor(hueClass),
              ),
            ],
          ),
          if (analysis?.storagePath case final storagePath?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton.icon(
                onPressed: () => _showImage(context, storagePath),
                icon: const Icon(Icons.image_outlined),
                label: const Text('View stored image'),
              ),
            ),
          if (conflict)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'The recorded methods disagree. Review both observations; '
                'AquaSense does not combine them into a single result.',
                style: TextStyle(color: AppColors.spoiled, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  void _showImage(BuildContext context, String storagePath) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: FutureBuilder<Uint8List?>(
          future: FirebaseService.downloadImage(storagePath),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load the stored image: ${snapshot.error}');
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null) {
              return const Text('Stored image is unavailable.');
            }
            return Image.memory(bytes);
          },
        ),
      ),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    required this.samples,
    required this.calibrations,
    super.key,
  });

  final List<FishSample> samples;
  final List<Map<String, Object?>> calibrations;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String? _error;
  bool _working = false;
  String? _csvPreview;
  List<SensorReading> _readings = [];
  List<VisualAnalysisRecord> _analyses = [];

  Future<void> _exportCsv() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final csv = const ReportService().toCsv(
        widget.samples,
        readings: _readings,
        analyses: _analyses,
        calibrations: widget.calibrations,
      );
      await SharePlus.instance.share(
        ShareParams(
          title: 'AquaSense sample data',
          text: 'Recorded sample metadata exported from this workspace.',
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
            ),
          ],
          fileNameOverrides: const ['aqua-sense-samples.csv'],
        ),
      );
      if (mounted) {
        setState(() {
          _csvPreview = csv;
          _working = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = 'CSV export failed: $error';
          _working = false;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final bytes = await const ReportService().toPdf(
        widget.samples,
        readings: _readings,
        analyses: _analyses,
        calibrations: widget.calibrations,
      );
      await Printing.layoutPdf(
        name: 'aqua-sense-report.pdf',
        onLayout: (_) async => bytes,
      );
      if (mounted) setState(() => _working = false);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = 'PDF export failed: $error';
          _working = false;
        });
      }
    }
  }

  Future<void> _sharePdf() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final bytes = await const ReportService().toPdf(
        widget.samples,
        readings: _readings,
        analyses: _analyses,
        calibrations: widget.calibrations,
      );
      await SharePlus.instance.share(
        ShareParams(
          title: 'AquaSense research report',
          files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
          fileNameOverrides: const ['aqua-sense-report.pdf'],
        ),
      );
      if (mounted) setState(() => _working = false);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = 'PDF sharing failed: $error';
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(child: _reportBody());

  Widget _reportBody() {
    if (!FirebaseService.isReady || FirebaseService.currentUser == null) {
      return _reportContent();
    }
    return StreamBuilder<List<SensorReading>>(
      stream: FirebaseService.watchReadings(),
      builder: (context, readingSnapshot) {
        if (readingSnapshot.hasError) {
          return _UnavailableCard(
            title: 'Could not load readings for report',
            detail: '${readingSnapshot.error}',
            icon: Icons.error_outline,
          );
        }
        return StreamBuilder<List<VisualAnalysisRecord>>(
          stream: FirebaseService.watchAnalyses(),
          builder: (context, analysisSnapshot) {
            if (analysisSnapshot.hasError) {
              return _UnavailableCard(
                title: 'Could not load analyses for report',
                detail: '${analysisSnapshot.error}',
                icon: Icons.error_outline,
              );
            }
            if (readingSnapshot.connectionState == ConnectionState.waiting ||
                analysisSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingCard(
                message: 'Loading actual records for export…',
              );
            }
            _readings = readingSnapshot.data ?? [];
            _analyses = analysisSnapshot.data ?? [];
            return _reportContent();
          },
        );
      },
    );
  }

  Widget _reportContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading(
        'Reports',
        subtitle: 'Exports contain recorded data only.',
      ),
      if (FirebaseService.isReady && FirebaseService.currentUser == null) ...[
        const SizedBox(height: 12),
        const _UnavailableCard(
          title: 'Signed out: cloud report data is unavailable',
          detail:
              'Exports include local sample and calibration records only. '
              'Sign in to include Firebase readings and visual analyses.',
          icon: Icons.cloud_off_outlined,
        ),
      ],
      const SizedBox(height: 18),
      NeumorphicCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Research data report',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.samples.length} sample record(s) · '
              '${_readings.length} pH reading(s) · '
              '${_analyses.length} visual analysis record(s) · '
              '${widget.calibrations.length} manual calibration(s)',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _working ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Preview / print PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _working ? null : _sharePdf,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _working ? null : _exportCsv,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Export CSV'),
                ),
                if (_working)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.spoiled)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 15),
      NeumorphicCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Included data',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Sample metadata, stored pH readings, stored visual analyses, '
              'and locally recorded manual calibration values. Missing '
              'data is omitted rather than invented.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (_csvPreview != null) ...[
              const SizedBox(height: 14),
              const Text(
                'CSV preview',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _csvPreview!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({
    required this.records,
    required this.onSave,
    super.key,
  });

  final List<Map<String, Object?>> records;
  final Future<void> Function(Map<String, Object?>) onSave;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _ph4Voltage = TextEditingController();
  final _ph7Voltage = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ph4Voltage.dispose();
    _ph7Voltage.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final voltage4 = double.parse(_ph4Voltage.text);
    final voltage7 = double.parse(_ph7Voltage.text);
    final difference = voltage7 - voltage4;
    if (difference.abs() < 0.05) {
      setState(() => _error = 'Buffer voltages are too close to calibrate.');
      return;
    }
    final slope = 3 / difference;
    final offset = 4 - slope * voltage4;
    final record = <String, Object?>{
      'bufferPh4Voltage': voltage4,
      'bufferPh7Voltage': voltage7,
      'slope': slope,
      'offset': offset,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'method': 'Manual entry; not verified by connected hardware',
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(record);
      if (mounted) {
        _ph4Voltage.clear();
        _ph7Voltage.clear();
        setState(() => _saving = false);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not save calibration record: $error';
          _saving = false;
        });
      }
    }
  }

  String? _validateVoltage(String? value) {
    final number = double.tryParse(value ?? '');
    if (number == null || !number.isFinite || number < 0 || number > 3.3) {
      return 'Enter a voltage from 0.00 to 3.30 V.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          'Two-point sensor calibration',
          subtitle: 'Manual record only; no hardware calibration is performed.',
        ),
        const SizedBox(height: 18),
        NeumorphicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Procedure',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                '1. Rinse the probe and place it in standard pH 4 buffer.\n'
                '2. Wait for a stable device voltage and record it.\n'
                '3. Rinse the probe, repeat with standard pH 7 buffer.\n'
                '4. Save the two voltage readings with the buffer temperature '
                'and operator noted in your lab record.',
                style: TextStyle(color: AppColors.muted, height: 1.65),
              ),
              const SizedBox(height: 12),
              const StatusPill(
                label: 'MANUAL VALUES — NOT HARDWARE VERIFIED',
                color: AppColors.moderate,
                icon: Icons.info_outline,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        NeumorphicCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record buffer voltages',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextFormField(
                        controller: _ph4Voltage,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _validateVoltage,
                        decoration: const InputDecoration(
                          labelText: 'Measured pH 4 voltage (V)',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: TextFormField(
                        controller: _ph7Voltage,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _validateVoltage,
                        decoration: const InputDecoration(
                          labelText: 'Measured pH 7 voltage (V)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save manual calibration record'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.spoiled),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        NeumorphicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audit history',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.records.isEmpty)
                const Text(
                  'No manual calibration records yet.',
                  style: TextStyle(color: AppColors.muted),
                ),
              for (final record in widget.records.take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.teal,
                  ),
                  title: Text(
                    'pH 4: ${record['bufferPh4Voltage']} V · '
                    'pH 7: ${record['bufferPh7Voltage']} V',
                  ),
                  subtitle: Text(
                    '${record['timestamp']} · ${record['method']}',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.thresholds,
    required this.onSave,
    required this.user,
    required this.onSignIn,
    required this.startupError,
    super.key,
  });

  final FreshnessThresholds thresholds;
  final Future<void> Function(FreshnessThresholds) onSave;
  final User? user;
  final VoidCallback onSignIn;
  final String? startupError;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final List<TextEditingController> _controllers;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = _thresholdValues(widget.thresholds)
        .map((value) => TextEditingController(text: _formatThreshold(value)))
        .toList();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thresholds != widget.thresholds) {
      final values = _thresholdValues(widget.thresholds);
      for (var i = 0; i < values.length; i++) {
        _controllers[i].text = _formatThreshold(values[i]);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveThresholds() async {
    final values = _controllers.map((controller) {
      return double.tryParse(controller.text.trim());
    }).toList();
    if (values.any((value) => value == null || !value.isFinite)) {
      setState(() => _error = 'Every threshold must be a valid number.');
      return;
    }
    final parsed = values.cast<double>();
    final phMin = parsed[0];
    final phFreshMax = parsed[1];
    final phModerateMax = parsed[2];
    final hueSpoiled = parsed[3];
    final hueFreshMin = parsed[4];
    final hueFreshMax = parsed[5];
    final hueModerateMax = parsed[6];
    if (phMin < 0 ||
        phFreshMax > 14 ||
        phModerateMax > 14 ||
        !(phMin < phFreshMax && phFreshMax <= phModerateMax)) {
      setState(() => _error = 'pH bands must be ordered within 0–14.');
      return;
    }
    if (hueSpoiled < 0 ||
        hueModerateMax > 360 ||
        !(hueSpoiled <= hueFreshMin &&
            hueFreshMin < hueFreshMax &&
            hueFreshMax <= hueModerateMax)) {
      setState(
        () => _error = 'Hue boundaries must be ordered within 0–360 degrees.',
      );
      return;
    }
    final thresholds = FreshnessThresholds(
      phFreshMin: phMin,
      phFreshMaxExclusive: phFreshMax,
      phModerateMaxInclusive: phModerateMax,
      hueSpoiledMinExclusive: hueSpoiled,
      hueFreshMinInclusive: hueFreshMin,
      hueFreshMaxExclusive: hueFreshMax,
      hueModerateMaxInclusive: hueModerateMax,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(thresholds);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Thresholds saved on this device.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save thresholds: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          'Device & system settings',
          subtitle:
              'Threshold values are stored locally and are not synced to '
              'Firebase.',
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: wide ? 1 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connections',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ConnectionRow(
                          label: 'Firebase',
                          status: FirebaseService.isReady
                              ? 'Configured'
                              : FirebaseService.isConfigured
                              ? 'Startup failed'
                              : 'Not configured',
                          connected: FirebaseService.isReady,
                        ),
                        const _DeviceStatusRows(),
                        if (widget.startupError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 9),
                            child: Text(
                              widget.startupError!,
                              style: const TextStyle(
                                color: AppColors.spoiled,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (widget.user == null && FirebaseService.isConfigured)
                          OutlinedButton.icon(
                            onPressed: widget.onSignIn,
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('Sign in'),
                          ),
                        if (widget.user != null)
                          Text(
                            'Signed in as ${widget.user!.email ?? widget.user!.uid}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: wide ? 14 : 0, height: wide ? 0 : 14),
                Flexible(
                  flex: wide ? 1 : 0,
                  fit: wide ? FlexFit.tight : FlexFit.loose,
                  child: NeumorphicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Classification thresholds',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Research starting parameters · Local override',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ThresholdInput(
                          controller: _controllers[0],
                          label: 'pH fresh minimum (inclusive)',
                        ),
                        _ThresholdInput(
                          controller: _controllers[1],
                          label: 'pH fresh upper bound (exclusive)',
                        ),
                        _ThresholdInput(
                          controller: _controllers[2],
                          label: 'pH moderate upper bound (inclusive)',
                        ),
                        const Divider(height: 22),
                        _ThresholdInput(
                          controller: _controllers[3],
                          label: 'Hue spoiled lower bound (exclusive)',
                        ),
                        _ThresholdInput(
                          controller: _controllers[4],
                          label: 'Hue fresh minimum (inclusive)',
                        ),
                        _ThresholdInput(
                          controller: _controllers[5],
                          label: 'Hue fresh upper bound (exclusive)',
                        ),
                        _ThresholdInput(
                          controller: _controllers[6],
                          label: 'Hue moderate upper bound (inclusive)',
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _saving ? null : _saveThresholds,
                          child: Text(
                            _saving ? 'Saving…' : 'Save thresholds locally',
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: _error!.startsWith('Thresholds saved')
                                    ? AppColors.fresh
                                    : AppColors.spoiled,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        const NeumorphicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Troubleshooting & research limits',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Configure Firebase values using --dart-define as documented '
                'in README.md.\n'
                '• Confirm database rules, device authentication, Wi-Fi and '
                'ESP32 heartbeat timestamps.\n'
                '• pH readings require calibrated hardware; hue depends on '
                'consistent lighting and ROI placement.\n'
                '• These research classifications are not regulatory food '
                'safety advice.',
                style: TextStyle(color: AppColors.muted, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ThresholdInput extends StatelessWidget {
  const _ThresholdInput({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.label,
    required this.status,
    required this.connected,
  });

  final String label;
  final String status;
  final bool connected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(
          connected ? Icons.check_circle : Icons.circle_outlined,
          size: 17,
          color: connected ? AppColors.fresh : AppColors.moderate,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          child: Text(
            status,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _DeviceStatusRows extends StatelessWidget {
  const _DeviceStatusRows();

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.isReady) {
      return const Column(
        children: [
          _ConnectionRow(
            label: 'ESP32 pH sensor',
            status: 'No device telemetry',
            connected: false,
          ),
          _ConnectionRow(
            label: 'ESP32-CAM',
            status: 'No device telemetry',
            connected: false,
          ),
        ],
      );
    }
    return StreamBuilder<List<DeviceStatus>>(
      stream: FirebaseService.watchDevices(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Could not read device status: ${snapshot.error}',
            style: const TextStyle(color: AppColors.spoiled, fontSize: 12),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(),
          );
        }
        final devices = {
          for (final device in snapshot.data ?? <DeviceStatus>[])
            device.id: device,
        };
        return Column(
          children: [
            _deviceRow('ESP32 pH sensor', devices['esp32-ph']),
            _deviceRow('ESP32-CAM', devices['esp32-cam']),
          ],
        );
      },
    );
  }

  Widget _deviceRow(String label, DeviceStatus? device) {
    if (device == null || device.lastSeen == null) {
      return _ConnectionRow(
        label: label,
        status: 'No heartbeat received',
        connected: false,
      );
    }
    final age = DateTime.now().toUtc().difference(device.lastSeen!);
    final connected = device.online && age < const Duration(minutes: 1);
    final lastSeen = device.lastSeen!.toLocal();
    return _ConnectionRow(
      label: label,
      status: connected
          ? 'Online · ${_shortDate(lastSeen)}'
          : 'Offline/stale · ${_shortDate(lastSeen)}',
      connected: connected,
    );
  }
}

class ReadingChart extends StatelessWidget {
  const ReadingChart({required this.readings, super.key});

  final List<SensorReading> readings;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return const _EmptyInline(
        icon: Icons.show_chart_rounded,
        message: 'No stored readings to chart.',
      );
    }
    return CustomPaint(
      painter: _ReadingChartPainter(readings.reversed.toList()),
      child: const SizedBox.expand(),
    );
  }
}

class _ReadingChartPainter extends CustomPainter {
  _ReadingChartPainter(this.readings);

  final List<SensorReading> readings;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 26.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(color: AppColors.muted, fontSize: 10);
    for (final value in [4, 6, 8, 10]) {
      final y = chart.bottom - (value - 4) / 8 * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _drawText(canvas, '$value', Offset(3, y - 6), labelStyle);
    }
    if (readings.length == 1) {
      final point = Offset(chart.center.dx, _yFor(readings.first.ph, chart));
      canvas.drawCircle(point, 5, Paint()..color = AppColors.teal);
      return;
    }
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < readings.length; i++) {
      final x = chart.left + i / (readings.length - 1) * chart.width;
      final point = Offset(x, _yFor(readings[i].ph, chart));
      points.add(point);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.aqua.withValues(alpha: 0.26),
            AppColors.aqua.withValues(alpha: 0.01),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(chart),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.teal
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 4, Paint()..color = AppColors.teal);
    _drawText(
      canvas,
      _shortDate(readings.first.timestamp.toLocal()),
      Offset(chart.left, chart.bottom + 8),
      labelStyle,
    );
    final lastLabel = _shortDate(readings.last.timestamp.toLocal());
    final textWidth = _measureText(lastLabel, labelStyle);
    _drawText(
      canvas,
      lastLabel,
      Offset(chart.right - textWidth, chart.bottom + 8),
      labelStyle,
    );
  }

  double _yFor(double value, Rect chart) {
    final normalized = ((value - 4) / 8).clamp(0.0, 1.0);
    return chart.bottom - normalized * chart.height;
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, offset);
  }

  double _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  bool shouldRepaint(covariant _ReadingChartPainter oldDelegate) =>
      oldDelegate.readings != readings;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: NeumorphicCard(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
              fontSize: 21,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _PhThresholdScale extends StatelessWidget {
  const _PhThresholdScale({required this.value, required this.thresholds});

  final double value;
  final FreshnessThresholds thresholds;

  @override
  Widget build(BuildContext context) {
    final bounds = [
      0.0,
      thresholds.phFreshMin,
      thresholds.phFreshMaxExclusive,
      thresholds.phModerateMaxInclusive,
      14.0,
    ];
    final colors = [
      AppColors.muted,
      AppColors.fresh,
      AppColors.moderate,
      AppColors.spoiled,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'pH threshold reference',
          style: TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, constraints) {
            final markerX =
                (value.clamp(0.0, 14.0) / 14.0 * constraints.maxWidth).clamp(
                  7.0,
                  constraints.maxWidth - 7.0,
                );
            return SizedBox(
              height: 29,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    height: 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          for (var index = 0; index < colors.length; index++)
                            Expanded(
                              flex: ((bounds[index + 1] - bounds[index]) * 100)
                                  .round()
                                  .clamp(1, 1400),
                              child: ColoredBox(
                                color: colors[index].withValues(alpha: 0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: markerX - 7,
                    top: 3,
                    child: Container(
                      width: 14,
                      height: 21,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x330A202C),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0', style: TextStyle(color: AppColors.muted, fontSize: 10)),
            Text(
              'Review',
              style: TextStyle(color: AppColors.muted, fontSize: 10),
            ),
            Text(
              'Fresh',
              style: TextStyle(color: AppColors.fresh, fontSize: 10),
            ),
            Text(
              'Moderate',
              style: TextStyle(color: AppColors.moderate, fontSize: 10),
            ),
            Text(
              'Spoiled',
              style: TextStyle(color: AppColors.spoiled, fontSize: 10),
            ),
            Text('14', style: TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Research bands only · not a food-safety determination',
          style: TextStyle(color: AppColors.muted, fontSize: 10),
        ),
      ],
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({
    required this.sample,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final FishSample sample;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: onTap,
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.aqua.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(Icons.science_outlined, color: AppColors.teal),
    ),
    title: Text(
      '${sample.id} · ${sample.fishType}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
    subtitle: Text(
      '${_shortDate(sample.collectedAt)} · '
      '${sample.operatorName.isEmpty ? 'Operator not specified' : sample.operatorName}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: onEdit == null && onDelete == null
        ? null
        : PopupMenuButton<String>(
            tooltip: 'Sample actions',
            onSelected: (value) {
              if (value == 'edit') onEdit?.call();
              if (value == 'delete') onDelete?.call();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit metadata')),
              PopupMenuItem(value: 'delete', child: Text('Delete sample')),
            ],
          ),
  );
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.title,
    required this.detail,
    required this.icon,
    this.actionLabel,
    this.onPressed,
  });

  final String title;
  final String detail;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => NeumorphicCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.moderate, size: 28),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              if (actionLabel != null && onPressed != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(onPressed: onPressed, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => NeumorphicCard(
    child: Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(message, style: const TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _Observation extends StatelessWidget {
  const _Observation({
    required this.title,
    required this.value,
    required this.timestamp,
    required this.color,
  });

  final String title;
  final String value;
  final DateTime? timestamp;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 270,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        if (timestamp != null)
          Text(
            timestamp!.toLocal().toString(),
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
      ],
    ),
  );
}

Color _classColor(FreshnessClass? value) => switch (value) {
  FreshnessClass.fresh => AppColors.fresh,
  FreshnessClass.moderate => AppColors.moderate,
  FreshnessClass.spoiled => AppColors.spoiled,
  FreshnessClass.review => AppColors.muted,
  null => AppColors.muted,
};

List<double> _thresholdValues(FreshnessThresholds thresholds) => [
  thresholds.phFreshMin,
  thresholds.phFreshMaxExclusive,
  thresholds.phModerateMaxInclusive,
  thresholds.hueSpoiledMinExclusive,
  thresholds.hueFreshMinInclusive,
  thresholds.hueFreshMaxExclusive,
  thresholds.hueModerateMaxInclusive,
];

String _formatThreshold(double value) =>
    value == value.truncateToDouble() ? value.toStringAsFixed(0) : '$value';

String _shortDate(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
