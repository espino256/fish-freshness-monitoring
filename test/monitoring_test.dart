import 'dart:typed_data';
import 'package:aqua_sense/models/telemetry.dart';
import 'package:aqua_sense/screens/history_screen.dart';
import 'package:aqua_sense/services/camera_service.dart';
import 'package:aqua_sense/services/gill_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('pH boundaries match physical GPIO firmware policy', () {
    for (final value in [0.0, 6.4999]) {
      expect(classifyPh(value), FishStatus.fresh);
    }
    for (final value in [6.5, 7.1999]) {
      expect(classifyPh(value), FishStatus.moderate);
    }
    for (final value in [7.2, 14.0]) {
      expect(classifyPh(value), FishStatus.spoiled);
    }
    for (final value in [double.nan, double.infinity, -1.0, 14.01]) {
      expect(() => classifyPh(value), throwsFormatException);
    }
  });
  test('telemetry rejects rail values and malformed fields', () {
    final data = <String, Object>{
      'deviceId': 'sensor',
      'ph': 6.5,
      'adcRaw': 2048,
      'measuredVoltage': 1.65,
      'timestamp': 1700000000000,
    };
    final reading = Telemetry.parse('r', data);
    expect(reading.nominalVoltage, closeTo(1.6504, 0.001));
    expect(
      reading.isStale(DateTime.fromMillisecondsSinceEpoch(1700000021000)),
      isTrue,
    );
    for (final invalid in [
      {'adcRaw': 0},
      {'adcRaw': 4095},
      {'ph': double.nan},
      {'timestamp': 'bad'},
      {'deviceId': ''},
    ]) {
      expect(
        () => Telemetry.parse('bad', {...data, ...invalid}),
        throwsFormatException,
      );
    }
  });
  test(
    'JPEG parser handles split markers, multipart headers and multiple frames',
    () {
      final parser = JpegFrames();
      expect(parser.add([1, 2, 255]), isEmpty);
      expect(parser.add([216, 10, 255]), isEmpty);
      final result = parser.add([217, 13, 10, 255, 216, 20, 255, 217]);
      expect(result, hasLength(2));
      expect(result.first, [255, 216, 10, 255, 217]);
      expect(result.last, [255, 216, 20, 255, 217]);
      expect(
        () => parser.add(List.filled(JpegFrames.maxBytes + 1, 0)),
        throwsFormatException,
      );
    },
  );
  test('camera rejects public HTTP and URLs that can leak credentials', () {
    for (final url in [
      'http://example.com',
      'file:///tmp',
      'http://user:pass@192.168.1.2',
      'http://192.168.1.2/path',
      'http://192.168.1.2?token=bad',
    ]) {
      expect(
        () => CameraService(url, 'http://192.168.1.2:81', 'some-password'),
        throwsFormatException,
      );
    }
    final camera = CameraService(
      'http://192.168.1.2',
      'http://192.168.1.2:81',
      'some-password',
    );
    camera.close();
  });
  test(
    'HSV red wraparound is fresh and neutral/dark images require recapture',
    () {
      Uint8List image(int r, int g, int b) {
        final source = img.Image(width: 200, height: 200);
        img.fill(source, color: img.ColorRgb8(r, g, b));
        return img.encodeJpg(source);
      }

      expect(analyzeGills(image(220, 20, 30)).classification, 'Fresh');
      expect(analyzeGills(image(20, 220, 20)).classification, 'Spoiled');
      expect(() => analyzeGills(image(120, 120, 120)), throwsFormatException);
      expect(() => analyzeGills(image(5, 0, 0)), throwsFormatException);
      expect(
        () => analyzeGills(Uint8List.fromList([1, 2])),
        throwsFormatException,
      );
    },
  );
  test('CSV quotes external values and prevents formula execution', () {
    final row = Telemetry(
      id: 'r',
      deviceId: '=HYPERLINK("bad")',
      ph: 6.5,
      adcRaw: 2048,
      measuredVoltage: 1.65,
      timestamp: DateTime.utc(2026),
    );
    final csv = historyCsv([row]);
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains('""bad""'));
    expect(csv, contains('2026-01-01T00:00:00.000Z'));
  });
}
