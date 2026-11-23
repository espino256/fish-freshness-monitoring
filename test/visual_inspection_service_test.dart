import 'dart:typed_data';

import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/services/visual_inspection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List checkerboard({img.Format format = img.Format.uint8}) {
    final image = img.Image(width: 120, height: 120, format: format);
    final scale = format == img.Format.uint16 ? 257 : 1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final light = ((x ~/ 10) + (y ~/ 10)).isEven;
        image.setPixelRgb(
          x,
          y,
          (light ? 60 : 210) * scale,
          (light ? 80 : 180) * scale,
          70 * scale,
        );
      }
    }
    return img.encodePng(image);
  }

  test('corrupt images are inconclusive rather than classified', () {
    final result = VisualInspectionService.inspect(
      VisualInspectionRequest(Uint8List.fromList([1, 2, 3]), FishPart.gills),
    );
    expect(result.classification, 'Inconclusive');
    expect(result.isImageUsable, isFalse);
  });

  for (final part in FishPart.values) {
    test('${part.label} has no enabled model, even for a detailed image', () {
      final result = VisualInspectionService.inspect(
        VisualInspectionRequest(checkerboard(), part),
      );
      expect(result.part, part);
      expect(result.width, 120);
      expect(result.height, 120);
      expect(result.isImageUsable, isTrue);
      expect(result.outcome, VisualFreshness.inconclusive);
      expect(result.reason, contains('No validated model'));
      expect(result.reason, contains(part.label));
      expect(result.reason, contains('has not been verified'));
      expect([
        result.hue,
        result.saturation,
        result.value,
        result.redFraction,
        result.usableFraction,
      ], everyElement(isNull));
    });
  }

  test('16-bit PNG quality checks use normalized channels', () {
    final result = VisualInspectionService.inspect(
      VisualInspectionRequest(
        checkerboard(format: img.Format.uint16),
        FishPart.gills,
      ),
    );
    expect(result.isImageUsable, isTrue);
    expect(result.outcome, VisualFreshness.inconclusive);
  });

  for (final (level, reason) in [
    (0, 'too dark'),
    (255, 'overexposed'),
    (128, 'too little detail'),
  ]) {
    test('$reason image is rejected without a prediction', () {
      final image = img.Image(width: 120, height: 120);
      img.fill(image, color: img.ColorRgb8(level, level, level));
      final result = VisualInspectionService.inspect(
        VisualInspectionRequest(img.encodePng(image), FishPart.skinScales),
      );
      expect(result.isImageUsable, isFalse);
      expect(result.outcome, VisualFreshness.inconclusive);
      expect(result.reason, contains(reason));
    });
  }

  test('small images and oversized uploads are inconclusive', () {
    final small = VisualInspectionService.inspect(
      VisualInspectionRequest(
        img.encodePng(img.Image(width: 99, height: 120)),
        FishPart.eyes,
      ),
    );
    expect(small.isImageUsable, isFalse);
    expect(small.reason, contains('100 × 100'));
    expect(small.outcome, VisualFreshness.inconclusive);
    final oversized = VisualInspectionService.inspect(
      VisualInspectionRequest(Uint8List(10 * 1024 * 1024 + 1), FishPart.gills),
    );
    expect(oversized.outcome, VisualFreshness.inconclusive);
    expect(oversized.reason, contains('10 MiB'));
  });

  test('unavailable and non-finite measurements render N/A without units', () {
    for (final value in <double?>[
      null,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(formatImageMeasurement(value), 'N/A');
      expect(formatImageMeasurement(value, percentage: true), 'N/A');
      expect(formatImageMeasurement(value, unit: '°'), 'N/A');
    }
    expect(formatImageMeasurement(double.maxFinite, percentage: true), 'N/A');
    expect(formatImageMeasurement(0, percentage: true), '0.0%');
    expect(formatImageMeasurement(0.125, percentage: true), '12.5%');
    expect(formatImageMeasurement(120, unit: '°'), '120.0°');
  });

  test('a readable selected region remains inconclusive without a model', () {
    final image = img.Image(width: 120, height: 120);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final light = ((x ~/ 10) + (y ~/ 10)).isEven;
        image.setPixelRgb(x, y, light ? 60 : 210, light ? 80 : 180, 70);
      }
    }
    final result = VisualInspectionService.inspect(
      VisualInspectionRequest(img.encodeJpg(image), FishPart.eyes),
    );
    expect(result.part, FishPart.eyes);
    expect(result.isImageUsable, isTrue);
    expect(result.classification, 'Inconclusive');
  });
}
