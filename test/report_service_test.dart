import 'package:csv/csv.dart' as csv_codec;
import 'package:aqua_sense/models/fish_sample.dart';
import 'package:aqua_sense/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sample = FishSample(
    id: 'FS-20261020-ABC',
    fishType: 'Milkfish café',
    details: 'Gill sample',
    collectedAt: DateTime.utc(2026, 10, 20),
    operatorName: 'Researcher',
    remarks: 'Gill cover’s hue — verified manually',
  );

  test('CSV contains recorded metadata and no invented readings', () {
    final csv = const ReportService().toCsv([sample]);
    expect(csv, contains(sample.id));
    expect(csv, contains('Milkfish café'));
    expect(csv, contains('Sample'));
    expect(csv, contains('Gill cover’s hue — verified manually'));
    expect(csv, isNot(contains('Simulated')));
  });

  test('CSV keeps calibration voltages out of pH and hue columns', () {
    final csv = const ReportService().toCsv(
      [],
      calibrations: [
        {
          'timestamp': '2026-10-20T00:00:00Z',
          'method': 'Two-point',
          'bufferPh4Voltage': 2.41,
          'bufferPh7Voltage': 1.83,
        },
      ],
    );
    final rows = csv_codec.csv.decode(csv);
    expect(rows.first, contains('Buffer pH 4 voltage (V)'));
    expect(rows.first, contains('Buffer pH 7 voltage (V)'));
    expect(rows[1][7], isEmpty);
    expect(rows[1][8], isEmpty);
    expect(rows[1][11], '2.41');
    expect(rows[1][12], '1.83');
    expect(rows[1][13], 'Manual; not hardware verified');
  });

  test('CSV exports readings and visual-analysis records to their columns', () {
    final csv = const ReportService().toCsv(
      [sample],
      readings: [
        SensorReading(
          id: 'reading-1',
          ph: 6.5,
          timestamp: DateTime.utc(2026, 10, 20),
          sampleId: sample.id,
          deviceId: 'esp32-ph',
        ),
      ],
      analyses: [
        VisualAnalysisRecord(
          id: 'analysis-1',
          sampleId: sample.id,
          meanHue: 24.5,
          classification: 'Fresh',
          timestamp: DateTime.utc(2026, 10, 20),
          storagePath: 'samples/${sample.id}/images/gill.jpg',
        ),
      ],
    );
    final rows = csv_codec.csv.decode(csv);

    expect(rows[1][0], 'Sample');
    expect(rows[2][0], 'pH reading');
    expect(rows[2][7], '6.5');
    expect(rows[3][0], 'Visual analysis');
    expect(rows[3][8], '24.5');
    expect(rows[3][10], 'samples/${sample.id}/images/gill.jpg');
  });

  test('creates a Unicode-font PDF report for available records', () async {
    final bytes = await const ReportService().toPdf(
      [sample],
      readings: [
        SensorReading(
          id: 'reading-1',
          ph: 6.5,
          timestamp: DateTime.utc(2026, 10, 20),
          sampleId: sample.id,
        ),
      ],
      analyses: [
        VisualAnalysisRecord(
          id: 'analysis-1',
          sampleId: sample.id,
          meanHue: 24.5,
          classification: 'Fresh',
          timestamp: DateTime.utc(2026, 10, 20),
        ),
      ],
      calibrations: [
        {
          'timestamp': '2026-10-20T00:00:00Z',
          'bufferPh4Voltage': 2.41,
          'bufferPh7Voltage': 1.83,
        },
      ],
    );
    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(String.fromCharCodes(bytes), contains('Roboto'));
  });
}
