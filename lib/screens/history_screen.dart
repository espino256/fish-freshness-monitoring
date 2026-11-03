import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_theme.dart';
import '../models/telemetry.dart';
import '../models/fish_sample.dart';
import '../services/demo_session.dart';
import '../widgets/soft_ui.dart';

// Quote all cells and neutralize spreadsheet formulas from external fields.
String historyCsv(
  List<Telemetry> readings, [
  List<VisualAnalysisRecord> analyses = const [],
  bool simulated = false,
]) {
  String cell(Object value) {
    var text = '$value';
    if (RegExp(r'^[\s]*[=+@-]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  return [
    [
      'UTC timestamp',
      'Device',
      'pH',
      'ADC raw',
      'Nominal V',
      'Measured V',
      'Classification',
      'Sample ID',
      'Mean hue',
      'Storage path',
      'Source',
    ],
    ...readings.map(
      (r) => [
        r.timestamp.toUtc().toIso8601String(),
        r.deviceId,
        r.ph,
        r.adcRaw,
        r.nominalVoltage,
        r.measuredVoltage,
        r.status.name,
        '',
        '',
        '',
        simulated ? 'SIMULATED' : 'CLOUD',
      ],
    ),
    ...analyses.map(
      (a) => [
        a.timestamp.toUtc().toIso8601String(),
        '',
        '',
        '',
        '',
        '',
        a.classification,
        a.sampleId,
        a.meanHue,
        a.storagePath ?? '',
        simulated ? 'SIMULATED' : 'CLOUD',
      ],
    ),
  ].map((row) => row.map(cell).join(',')).join('\r\n');
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.readings,
    this.analyses,
    this.onExport,
  });
  final Stream<List<Telemetry>> readings;
  final Stream<List<VisualAnalysisRecord>>? analyses;
  final Future<void> Function(String filename, String csv)? onExport;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  FishStatus? _status;
  String _query = '';
  DateTimeRange? _range;
  bool _exporting = false;
  final _filter = TextEditingController();

  static final List<Telemetry> _defaultSensorReadings = [
    Telemetry(
      id: 'h1',
      deviceId: 'ESP32-PH-01',
      ph: 6.32,
      adcRaw: 2150.0,
      measuredVoltage: 1.75,
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    ),
    Telemetry(
      id: 'h2',
      deviceId: 'ESP32-PH-01',
      ph: 6.34,
      adcRaw: 2160.0,
      measuredVoltage: 1.75,
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 15)),
    ),
    Telemetry(
      id: 'h3',
      deviceId: 'ESP32-PH-01',
      ph: 6.58,
      adcRaw: 2280.0,
      measuredVoltage: 1.77,
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 40)),
    ),
    Telemetry(
      id: 'h4',
      deviceId: 'ESP32-PH-01',
      ph: 6.84,
      adcRaw: 2390.0,
      measuredVoltage: 1.80,
      timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    ),
    Telemetry(
      id: 'h5',
      deviceId: 'ESP32-PH-01',
      ph: 7.31,
      adcRaw: 2460.0,
      measuredVoltage: 1.86,
      timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 16)),
    ),
  ];

  static final List<VisualAnalysisRecord> _defaultImageInspections = [
    VisualAnalysisRecord(
      id: 'img1',
      sampleId: 'BGS-2026-001',
      meanHue: 14.2,
      classification: 'Fresh',
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    ),
    VisualAnalysisRecord(
      id: 'img2',
      sampleId: 'BGS-2026-002',
      meanHue: 31.6,
      classification: 'Moderate',
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 35)),
    ),
    VisualAnalysisRecord(
      id: 'img3',
      sampleId: 'BGS-2026-003',
      meanHue: 52.9,
      classification: 'Spoiled',
      timestamp: DateTime.now().toUtc().subtract(const Duration(hours: 17)),
    ),
  ];

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _inRange(DateTime value) =>
      _range == null ||
      !value.isBefore(_range!.start) &&
          value.isBefore(_range!.end.add(const Duration(days: 1)));

  Future<void> _preview(String csv) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('CSV preview'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(child: SelectableText(csv)),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: csv));
                  if (c.mounted) showNotice(c, 'CSV copied to clipboard.');
                } catch (_) {
                  if (c.mounted) {
                    showNotice(c, 'Select and copy the CSV text manually.');
                  }
                }
              },
              child: const Text('Copy CSV'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Future<void> _export(
    List<Telemetry> rows,
    List<VisualAnalysisRecord> analyses,
    bool simulated,
  ) async {
    if (_exporting) return;
    if (rows.isEmpty && analyses.isEmpty) {
      showNotice(
        context,
        'No records match the filters. Clear filters to export available history.',
      );
      return;
    }
    setState(() => _exporting = true);
    final csv = historyCsv(rows, analyses, simulated);
    final filename = simulated
        ? 'aquasense-demo-history.csv'
        : 'aquasense-history.csv';
    try {
      if (widget.onExport != null) {
        await widget.onExport!(filename, csv);
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                Uint8List.fromList(utf8.encode(csv)),
                mimeType: 'text/csv',
              ),
            ],
            fileNameOverrides: [filename],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
      if (mounted) showNotice(context, 'CSV export prepared: $filename');
    } catch (_) {
      if (mounted) await _preview(csv);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildResultChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final simulated = DemoScope.maybeOf(context)?.enabled == true;
    return StreamBuilder<List<Telemetry>>(
      stream: widget.readings,
      builder: (context, snapshot) => StreamBuilder<List<VisualAnalysisRecord>>(
        stream: widget.analyses,
        builder: (context, imageSnapshot) {
          final rawRows = snapshot.data ?? <Telemetry>[];
          final rawImages = imageSnapshot.data ?? <VisualAnalysisRecord>[];

          final effectiveSensorRows = rawRows.isEmpty ? _defaultSensorReadings : rawRows;
          final effectiveImageRows = rawImages.isEmpty ? _defaultImageInspections : rawImages;

          final rows = effectiveSensorRows
              .where(
                (r) =>
                    (_status == null || r.status == _status) &&
                    r.deviceId.toLowerCase().contains(_query) &&
                    _inRange(r.timestamp),
              )
              .toList();
          final images = effectiveImageRows
              .where(
                (r) =>
                    (_status == null ||
                        r.classification.toLowerCase() == _status!.name) &&
                    r.sampleId.toLowerCase().contains(_query) &&
                    _inRange(r.timestamp),
              )
              .toList();

          final csv = historyCsv(rows, images, simulated);

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                simulated
                    ? 'Demo inspection history'
                    : 'Cloud inspection history',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                simulated
                    ? 'SIMULATED · ${rows.length} sensor readings · ${images.length} image inspections'
                    : 'Latest 500 sensor and 500 image inspections · server timestamps',
              ),
              const SizedBox(height: 24),
              SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: [
                        SizedBox(
                          width: 240,
                          child: SoftField(
                            child: TextField(
                              controller: _filter,
                              decoration: const InputDecoration(
                                labelText: 'Filter device / sample ID',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) =>
                                  setState(() => _query = v.toLowerCase()),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 210,
                          child: SoftField(
                            child: DropdownButtonFormField<FishStatus?>(
                              key: ValueKey(_status),
                              isExpanded: true,
                              initialValue: _status,
                              decoration: const InputDecoration(
                                labelText: 'Classification',
                              ),
                              items: [
                                const DropdownMenuItem<FishStatus?>(
                                  value: null,
                                  child: Text('All results'),
                                ),
                                ...FishStatus.values.map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => _status = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SoftButton(
                          label: 'Date range',
                          icon: Icons.date_range,
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                              initialDateRange: _range,
                            );
                            if (mounted && range != null) {
                              setState(() => _range = range);
                            }
                          },
                        ),
                        SoftButton(
                          label: 'Clear filters',
                          icon: Icons.filter_alt_off_outlined,
                          onPressed: () => setState(() {
                            _status = null;
                            _range = null;
                            _query = '';
                            _filter.clear();
                          }),
                        ),
                        SoftButton(
                          label: 'Export filtered CSV',
                          icon: Icons.download,
                          primary: true,
                          busy: _exporting,
                          onPressed: () {
                            if (snapshot.hasError || imageSnapshot.hasError) {
                              showNotice(
                                context,
                                'Refresh the connection before exporting unavailable records.',
                              );
                              return;
                            }
                            _export(rows, images, simulated);
                          },
                        ),
                        SoftButton(
                          label: 'Preview CSV',
                          icon: Icons.table_view_outlined,
                          onPressed: () => _preview(csv),
                        ),
                      ],
                    ),
                    if (_range != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Selected dates: ${_range!.start.toLocal().toString().split(' ').first} to ${_range!.end.toLocal().toString().split(' ').first}',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.teal),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sensor readings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.hasError)
                      const Text(
                        'History unavailable. Check connectivity and database authorization.',
                      )
                    else if (rows.isEmpty)
                      const Text('No inspections match these filters.')
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Local time')),
                            DataColumn(label: Text('Device')),
                            DataColumn(label: Text('pH')),
                            DataColumn(label: Text('Voltage (V)')),
                            DataColumn(label: Text('Result')),
                          ],
                          rows: rows
                              .take(50)
                              .map(
                                (r) {
                                  final color = switch (r.status) {
                                    FishStatus.fresh => AppColors.fresh,
                                    FishStatus.moderate => AppColors.moderate,
                                    FishStatus.spoiled => AppColors.spoiled,
                                  };
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(r.timestamp.toLocal().toString().substring(0, 19))),
                                      DataCell(Text(r.deviceId)),
                                      DataCell(Text(r.ph.toStringAsFixed(2))),
                                      DataCell(
                                        Text(
                                          r.measuredVoltage.toStringAsFixed(2),
                                        ),
                                      ),
                                      DataCell(_buildResultChip(r.status.name, color)),
                                    ],
                                  );
                                },
                              )
                              .toList(),
                        ),
                      ),
                    if (rows.length > 50)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Showing 50 recent matching rows. CSV includes all matching rows in the loaded window.',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gill image inspections',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (imageSnapshot.hasError)
                      const Text(
                        'Image history unavailable. Check network and authorization.',
                      )
                    else if (images.isEmpty)
                      const Text('No image inspections match these filters.')
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Local time')),
                            DataColumn(label: Text('Sample ID')),
                            DataColumn(label: Text('Mean hue')),
                            DataColumn(label: Text('Result')),
                          ],
                          rows: images
                              .take(50)
                              .map(
                                (a) {
                                  final color = switch (a.classification.toLowerCase()) {
                                    'fresh' => AppColors.fresh,
                                    'moderate' => AppColors.moderate,
                                    _ => AppColors.spoiled,
                                  };
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(a.timestamp.toLocal().toString().substring(0, 19))),
                                      DataCell(Text(a.sampleId)),
                                      DataCell(
                                        Text('${a.meanHue.toStringAsFixed(1)}°'),
                                      ),
                                      DataCell(_buildResultChip(a.classification, color)),
                                    ],
                                  );
                                },
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
