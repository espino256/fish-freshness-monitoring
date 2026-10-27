import 'package:aqua_sense/models/classification.dart';
import 'package:aqua_sense/models/fish_sample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const thresholds = FreshnessThresholds();

  group('pH classification boundaries', () {
    test('assigns documented boundaries to a single range', () {
      expect(thresholds.classifyPh(6.2), FreshnessClass.fresh);
      expect(thresholds.classifyPh(6.499), FreshnessClass.fresh);
      expect(thresholds.classifyPh(6.5), FreshnessClass.moderate);
      expect(thresholds.classifyPh(7.0), FreshnessClass.moderate);
      expect(thresholds.classifyPh(7.001), FreshnessClass.spoiled);
      expect(thresholds.classifyPh(14), FreshnessClass.spoiled);
      expect(thresholds.classifyPh(0), FreshnessClass.review);
      expect(thresholds.classifyPh(6.199), FreshnessClass.review);
    });

    test('rejects missing, non-finite, and impossible sensor values', () {
      expect(thresholds.classifyPh(null), isNull);
      expect(thresholds.classifyPh(double.nan), isNull);
      expect(thresholds.classifyPh(double.infinity), isNull);
      expect(thresholds.classifyPh(-0.1), isNull);
      expect(thresholds.classifyPh(14.1), isNull);
    });
  });

  group('hue classification boundaries', () {
    test('classifies threshold boundaries without overlapping ranges', () {
      expect(thresholds.classifyHue(0), FreshnessClass.spoiled);
      expect(thresholds.classifyHue(4.99), FreshnessClass.spoiled);
      expect(thresholds.classifyHue(5), FreshnessClass.fresh);
      expect(thresholds.classifyHue(24.99), FreshnessClass.fresh);
      expect(thresholds.classifyHue(25), FreshnessClass.moderate);
      expect(thresholds.classifyHue(45), FreshnessClass.moderate);
      expect(thresholds.classifyHue(45.01), FreshnessClass.spoiled);
      expect(thresholds.classifyHue(360), FreshnessClass.spoiled);
    });

    test('rejects missing and out-of-domain hue values', () {
      expect(thresholds.classifyHue(null), isNull);
      expect(thresholds.classifyHue(double.nan), isNull);
      expect(thresholds.classifyHue(-1), isNull);
      expect(thresholds.classifyHue(361), isNull);
    });
  });

  test('RGB hue helper reports missing/invalid input explicitly', () {
    expect(meanHueFromRgb([]), isNull);
    expect(meanHueFromRgb([(256, 0, 0)]), isNull);
    expect(meanHueFromRgb([(255, 0, 0)]), 0);
    expect(meanHueFromRgb([(255, 0, 0), (255, 0, 1)]), greaterThan(359));
  });

  test('sample identifiers are unique for separate generation instants', () {
    final first = FishSample.createId(DateTime.utc(2026, 1, 1));
    final second = FishSample.createId(
      DateTime.utc(2026, 1, 1).add(const Duration(microseconds: 1)),
    );
    expect(first, startsWith('FS-20260101-'));
    expect(second, isNot(first));
  });

  test('sensor readings reject absent and invalid values', () {
    expect(
      () => SensorReading.fromFirebase('r1', {'timestamp': 100}),
      throwsFormatException,
    );
    expect(
      () => SensorReading.fromFirebase('r1', {'ph': 15, 'timestamp': 100}),
      throwsFormatException,
    );
  });
}
