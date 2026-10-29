import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
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

  @override
  Widget build(BuildContext context) {
    final simulated = DemoScope.maybeOf(context)?.enabled == true;
    return StreamBuilder<List<Telemetry>>(
      stream: widget.readings,
      builder: (context, snapshot) => StreamBuilder<List<VisualAnalysisRecord>>(
        stream: widget.analyses,
        builder: (context, imageSnapshot) {
          final rows = (snapshot.data ?? <Telemetry>[])
              .where(
                (r) =>
                    (_status == null || r.status == _status) &&
                    r.deviceId.toLowerCase().contains(_query) &&
                    _inRange(r.timestamp),
              )
              .toList();
          final images = (imageSnapshot.data ?? <VisualAnalysisRecord>[])
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
                      'pH readings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.hasError)
                      const Text(
                        'History unavailable. Check connectivity and database authorization.',
                      )
                    else if (!snapshot.hasData)
                      const LinearProgressIndicator()
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
                                (r) => DataRow(
                                  cells: [
                                    DataCell(Text('${r.timestamp.toLocal()}')),
                                    DataCell(Text(r.deviceId)),
                                    DataCell(Text(r.ph.toStringAsFixed(2))),
                                    DataCell(
                                      Text(
                                        r.measuredVoltage.toStringAsFixed(3),
                                      ),
                                    ),
                                    DataCell(Text(r.status.name)),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (rows.length > 50)
                      const Text(
                        'Showing 50 recent matching rows. CSV includes all matching rows in the loaded window.',
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
                            DataColumn(label: Text('Experimental result')),
                          ],
                          rows: images
                              .take(50)
                              .map(
                                (a) => DataRow(
                                  cells: [
                                    DataCell(Text('${a.timestamp.toLocal()}')),
                                    DataCell(Text(a.sampleId)),
                                    DataCell(
                                      Text(a.meanHue.toStringAsFixed(1)),
                                    ),
                                    DataCell(Text(a.classification)),
                                  ],
                                ),
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
