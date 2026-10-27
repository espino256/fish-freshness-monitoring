import 'package:csv/csv.dart' as csv_codec;
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/fish_sample.dart';

class ReportService {
  const ReportService();

  String toCsv(
    List<FishSample> samples, {
    List<SensorReading> readings = const [],
    List<VisualAnalysisRecord> analyses = const [],
    List<Map<String, Object?>> calibrations = const [],
  }) {
    final rows = <List<Object?>>[
      [
        'Record type',
        'Sample ID',
        'Fish type',
        'Details',
        'Timestamp',
        'Operator',
        'Notes',
        'pH',
        'Mean hue',
        'Classification',
        'Storage path',
        'Buffer pH 4 voltage (V)',
        'Buffer pH 7 voltage (V)',
        'Calibration status',
      ],
      ...samples.map(
        (sample) => [
          'Sample',
          sample.id,
          sample.fishType,
          sample.details,
          sample.collectedAt.toUtc().toIso8601String(),
          sample.operatorName,
          sample.remarks,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ],
      ),
      ...readings.map(
        (reading) => [
          'pH reading',
          reading.sampleId ?? '',
          '',
          '',
          reading.timestamp.toUtc().toIso8601String(),
          '',
          '',
          reading.ph,
          '',
          '',
          '',
          '',
          '',
          '',
        ],
      ),
      ...analyses.map(
        (analysis) => [
          'Visual analysis',
          analysis.sampleId,
          '',
          '',
          analysis.timestamp.toUtc().toIso8601String(),
          '',
          '',
          '',
          analysis.meanHue,
          analysis.classification,
          analysis.storagePath ?? '',
          '',
          '',
          '',
        ],
      ),
      ...calibrations.map(
        (calibration) => [
          'Manual calibration',
          '',
          '',
          '',
          calibration['timestamp'] ?? '',
          '',
          calibration['method'] ?? '',
          '',
          '',
          '',
          '',
          calibration['bufferPh4Voltage'] ?? '',
          calibration['bufferPh7Voltage'] ?? '',
          'Manual; not hardware verified',
        ],
      ),
    ];
    return csv_codec.csv.encode(rows);
  }

  Future<Uint8List> toPdf(
    List<FishSample> samples, {
    List<SensorReading> readings = const [],
    List<VisualAnalysisRecord> analyses = const [],
    List<Map<String, Object?>> calibrations = const [],
  }) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );
    document.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            'AquaSense research report',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Exported ${DateTime.now().toUtc().toIso8601String()} UTC'),
          pw.SizedBox(height: 18),
          pw.Text('Sample metadata (${samples.length})'),
          if (samples.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: const [
                'Sample ID',
                'Fish type',
                'Collected',
                'Operator',
                'Notes',
              ],
              data: samples
                  .map(
                    (sample) => [
                      sample.id,
                      sample.fishType,
                      sample.collectedAt.toUtc().toIso8601String(),
                      sample.operatorName,
                      sample.remarks,
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 16),
          pw.Text('pH readings (${readings.length})'),
          if (readings.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: const ['Sample ID', 'pH', 'Recorded at', 'Device'],
              data: readings
                  .map(
                    (reading) => [
                      reading.sampleId ?? 'Not linked',
                      reading.ph.toStringAsFixed(3),
                      reading.timestamp.toUtc().toIso8601String(),
                      reading.deviceId ?? 'Not reported',
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 16),
          pw.Text('Visual analyses (${analyses.length})'),
          if (analyses.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: const ['Sample ID', 'Mean hue', 'Classification', 'UTC'],
              data: analyses
                  .map(
                    (analysis) => [
                      analysis.sampleId,
                      analysis.meanHue.toStringAsFixed(2),
                      analysis.classification,
                      analysis.timestamp.toUtc().toIso8601String(),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 16),
          pw.Text('Calibration records (${calibrations.length})'),
          if (calibrations.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: const [
                'pH 4 voltage',
                'pH 7 voltage',
                'Timestamp',
                'Status',
              ],
              data: calibrations
                  .map(
                    (calibration) => [
                      '${calibration['bufferPh4Voltage']} V',
                      '${calibration['bufferPh7Voltage']} V',
                      '${calibration['timestamp']}',
                      'Manual; not hardware verified',
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Only records available at export time are included. Missing '
            'readings, classifications, and calibration data are not invented. '
            'Research thresholds are not food safety guarantees.',
          ),
        ],
      ),
    );
    return document.save();
  }
}
