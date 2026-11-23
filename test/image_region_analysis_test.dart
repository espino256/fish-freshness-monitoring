import 'dart:convert';
import 'dart:typed_data';

import 'package:aqua_sense/models/experimental_ai.dart';
import 'package:aqua_sense/models/image_region.dart';
import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/services/image_region_analysis_service.dart';
import 'package:aqua_sense/services/visual_inspection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/region_fixture.dart';

const center = ImageRegion(.25, .25, .75, .75);
const full = ImageRegion(0, 0, 1, 1);

void main() {
  test('RGB conversion has defined HSV units and undefined grayscale hue', () {
    final cases = <(double, double, double, double)>[
      (1, 0, 0, 0),
      (0, 1, 0, 120),
      (0, 0, 1, 240),
      (1, 0, 1, 300),
    ];
    for (final c in cases) {
      final hsv = ImageRegionAnalysisService.rgbToHsv(c.$1, c.$2, c.$3);
      expect(hsv.hue, c.$4);
      expect(hsv.saturation, 1);
      expect(hsv.value, 1);
    }
    for (final v in [0.0, .5, 1.0]) {
      final gray = ImageRegionAnalysisService.rgbToHsv(v, v, v);
      expect(gray.hue, isNull);
      expect(gray.saturation, 0);
      expect(gray.value, v);
    }
    final colored = ImageRegionAnalysisService.rgbToHsv(.8, .4, .2);
    expect(colored.hue, closeTo(20, 1e-12));
    expect(colored.saturation, closeTo(.75, 1e-12));
    expect(colored.value, .8);
    for (final invalid in [double.nan, double.infinity, -.01, 1.01]) {
      expect(
        () => ImageRegionAnalysisService.rgbToHsv(invalid, 0, 0),
        throwsArgumentError,
      );
    }
  });

  test(
    'circular hue wraps north, rejects cancellation and ignores nonfinite data',
    () {
      expect(
        ImageRegionAnalysisService.circularHueMean([359, 1]),
        closeTo(0, 1e-9),
      );
      expect(
        ImageRegionAnalysisService.circularHueMean([350, 10, double.nan]),
        closeTo(0, 1e-9),
      );
      expect(ImageRegionAnalysisService.circularHueMean([0, 180]), isNull);
      expect(ImageRegionAnalysisService.circularHueMean([]), isNull);
      expect(
        ImageRegionAnalysisService.circularHueMean([double.infinity]),
        isNull,
      );
    },
  );

  test('red-sector documented boundaries include 35 and 325 and wrap 360', () {
    for (final hue in [0.0, 35.0, 325.0, 359.9, 360.0, -1.0]) {
      expect(ImageRegionAnalysisService.isRedHue(hue), isTrue);
    }
    for (final hue in [35.001, 324.999, 120.0, double.nan, double.infinity]) {
      expect(ImageRegionAnalysisService.isRedHue(hue), isFalse);
    }
  });

  test('actual ROI pixels produce reproducible metrics without background', () {
    final image = regionFixture();
    final m = ImageRegionAnalysisService.analyze(image, center);
    expect(m.bounds!.left, 64);
    expect(m.bounds!.width, 128);
    expect(m.eligiblePixels, 16384);
    expect(m.usablePixels, 16384);
    expect(m.huePixels, 16384);
    expect(m.meanHue, closeTo(60, 1e-9));
    expect(m.meanSaturation, closeTo((.9 + 5 / 6) / 2, 1e-9));
    expect(m.meanValue, closeTo(160 / 255, 1e-9));
    expect(m.redFraction, .5);
    expect(m.usableFraction, 1);
    expect(
      m.focusVariance,
      greaterThan(ImageRegionAnalysisService.minimumFocusVariance),
    );
    // Evidence is calculated from the generated pixels, never an app default.
    // ignore: avoid_print
    print(
      'AQUASENSE_ROI_EVIDENCE ${jsonEncode({
        'fixture': 'synthetic RGB checker; not fish validation',
        'roi': [64, 64, 128, 128],
        'eligible': m.eligiblePixels,
        'usable': m.usablePixels,
        'hueSamples': m.huePixels,
        'hueDegrees': m.meanHue,
        'saturation': m.meanSaturation,
        'value': m.meanValue,
        'redFraction': m.redFraction,
        'usableFraction': m.usableFraction,
        'focusVariance': m.focusVariance,
      })}',
    );
    final includingBackground = ImageRegionAnalysisService.analyze(image, full);
    expect(includingBackground.meanSaturation, lessThan(m.meanSaturation!));
  });

  test('binary mask removes pixels before the usable-area denominator', () {
    final image = regionFixture();
    final mask = Uint8List(256 * 256);
    for (var y = 64; y < 192; y++) {
      for (var x = 64; x < 128; x++) {
        mask[y * 256 + x] = 1;
      }
    }
    // One quarter of selected pixels is black; excluded pixels outside the
    // selection are white and cannot contribute to either numerator.
    for (var y = 64; y < 96; y++) {
      for (var x = 64; x < 128; x++) {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
    final m = ImageRegionAnalysisService.analyze(
      image,
      full,
      selectionMask: mask,
    );
    expect(m.eligiblePixels, 8192);
    expect(m.usablePixels, 6144);
    expect(m.usableFraction, .75);
    expect(m.redFraction, .5);
  });

  test(
    'dark glare and transparent pixels are excluded, gray keeps S and V',
    () {
      final image = img.Image(width: 128, height: 128, numChannels: 4);
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          final v = ((x ~/ 4) + (y ~/ 4)).isEven ? 80 : 180;
          image.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      final gray = ImageRegionAnalysisService.analyze(image, full);
      expect(gray.meanHue, isNull);
      expect(gray.redFraction, isNull);
      expect(gray.meanSaturation, 0);
      expect(gray.meanValue, closeTo(130 / 255, 1e-9));
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 128; x++) {
          image.setPixelRgba(x, y, 255, 0, 0, 0);
        }
      }
      for (var y = 32; y < 64; y++) {
        for (var x = 0; x < 128; x++) {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
      for (var y = 64; y < 96; y++) {
        for (var x = 0; x < 128; x++) {
          image.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
      final m = ImageRegionAnalysisService.analyze(image, full);
      expect(m.eligiblePixels, 16384);
      expect(m.usablePixels, 4096);
      expect(m.usableFraction, .25);
      expect(m.meanHue, isNull);
      expect(m.meanValue, closeTo(130 / 255, 1e-9));
    },
  );

  test('low saturation keeps exposure samples but excludes unreliable hue', () {
    final image = img.Image(width: 128, height: 128);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 128; x++) {
        final v = ((x ~/ 4) + (y ~/ 4)).isEven ? 80 : 180;
        image.setPixelRgb(x, y, v, v - 1, v - 1);
      }
    }
    final m = ImageRegionAnalysisService.analyze(image, full);
    expect(m.usableFraction, 1);
    expect(m.huePixels, 0);
    expect(m.meanHue, isNull);
    expect(m.redFraction, isNull);
    expect(m.meanSaturation, closeTo((1 / 80 + 1 / 180) / 2, 1e-9));
  });

  test('16-bit samples are normalized by their real channel range', () {
    final image = img.Image(width: 128, height: 128, format: img.Format.uint16);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 128; x++) {
        final red = ((x ~/ 4) + (y ~/ 4)).isEven;
        image.setPixelRgb(x, y, red ? 51400 : 5140, red ? 5140 : 30840, 5140);
      }
    }
    final m = ImageRegionAnalysisService.analyze(image, full);
    expect(m.meanValue, closeTo(160 / 255, 1e-9));
    expect(m.meanHue, closeTo(60, 1e-9));
  });

  test(
    'invalid, tiny, empty masks and insufficient samples stay unavailable',
    () {
      final image = regionFixture();
      for (final region in [
        const ImageRegion(0, 0, 0, 1),
        const ImageRegion(-.1, 0, 1, 1),
        const ImageRegion(0, 0, 1.1, 1),
        const ImageRegion(double.nan, 0, 1, 1),
        const ImageRegion(0, 0, .02, .02),
      ]) {
        final m = ImageRegionAnalysisService.analyze(image, region);
        expect(m.meanHue, isNull);
        expect(m.meanValue, isNull);
        expect(m.usableFraction, isNull);
      }
      expect(full.pixels(0, 0), isNull);
      final empty = ImageRegionAnalysisService.analyze(
        image,
        full,
        selectionMask: Uint8List(65536),
      );
      expect(empty.reason, contains('No eligible pixels'));
      expect(empty.usableFraction, isNull);
      final mismatch = ImageRegionAnalysisService.analyze(
        image,
        full,
        selectionMask: Uint8List(5),
      );
      expect(mismatch.reason, contains('does not match'));
      final mask = Uint8List(65536);
      for (var x = 0; x < 30; x++) {
        mask[64 * 256 + 64 + x] = 1;
      }
      final insufficient = ImageRegionAnalysisService.analyze(
        image,
        full,
        selectionMask: mask,
      );
      expect(insufficient.meanValue, isNull);
      expect(insufficient.usableFraction, 1);
      expect(insufficient.reason, contains('At least 50'));
    },
  );

  test(
    'flat and smoothly blurred regions fail the documented detail proxy',
    () {
      final image = regionFixture();
      img.fill(image, color: img.ColorRgb8(100, 50, 50));
      var m = ImageRegionAnalysisService.analyze(image, full);
      expect(m.meanValue, isNull);
      expect(m.reason, contains('too little spatial detail'));
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          image.setPixelRgb(x, y, 80 + x ~/ 4, 20, 20);
        }
      }
      m = ImageRegionAnalysisService.analyze(image, full);
      expect(m.meanHue, isNull);
      expect(m.reason, contains('too little spatial detail'));
      final dark = img.Image(width: 128, height: 128);
      final unusable = ImageRegionAnalysisService.analyze(dark, full);
      expect(unusable.usableFraction, 0);
      expect(unusable.meanValue, isNull);
    },
  );

  test('ROI does not crop, normalize or reorder the model RGB tensor', () {
    final bytes = img.encodePng(regionFixture());
    final base = VisualInspectionService.prepare(
      VisualInspectionRequest(bytes, FishPart.gills),
    );
    final selected = VisualInspectionService.prepare(
      VisualInspectionRequest(bytes, FishPart.gills, region: center),
    );
    expect(base.inspection.isImageUsable, isTrue);
    expect(selected.input, orderedEquals(base.input!));
    expect(base.inspection.hue, isNull);
    expect(selected.inspection.hue, closeTo(60, 1e-9));
    final output = selected.inspection.withExperimentalAi(
      ExperimentalAiResult(
        model: ExperimentalFishModel.gills,
        status: ExperimentalAiStatus.completed,
        message: 'Test double only',
        scores: [.2, .3, .5],
      ),
    );
    expect(output.measurements, same(selected.inspection.measurements));
    expect(output.outcome, VisualFreshness.inconclusive);
  });

  test(
    'EXIF orientation and explicit rotation match displayed ROI coordinates',
    () {
      final original = img.Image(width: 120, height: 180);
      for (var y = 0; y < 180; y++) {
        for (var x = 0; x < 120; x++) {
          final light = ((x ~/ 4) + (y ~/ 4)).isEven;
          original.setPixelRgb(
            x,
            y,
            y < 90 ? (light ? 200 : 100) : 20,
            y >= 90 ? (light ? 180 : 100) : 20,
            20,
          );
        }
      }
      original.exif.imageIfd.orientation = 6;
      final bytes = img.encodeJpg(original, quality: 100);
      final preview = VisualInspectionService.preview(
        VisualInspectionRequest(bytes, FishPart.gills),
      );
      expect([preview.width, preview.height], [180, 120]);
      final oriented = img.decodePng(preview.bytes!)!;
      expect(
        oriented.getPixel(20, 20).g,
        greaterThan(oriented.getPixel(20, 20).r),
      );
      const right = ImageRegion(.55, 0, 1, 1);
      final measured = VisualInspectionService.inspect(
        VisualInspectionRequest(bytes, FishPart.gills, region: right),
      );
      expect(measured.hue, anyOf(lessThan(2), greaterThan(358)));
      final rotated = VisualInspectionService.preview(
        VisualInspectionRequest(bytes, FishPart.gills, quarterTurns: 1),
      );
      expect([rotated.width, rotated.height], [120, 180]);
      final twice = img.decodePng(rotated.bytes!)!;
      expect(twice.getPixel(20, 20).g, greaterThan(twice.getPixel(20, 20).r));
      const bottom = ImageRegion(0, .55, 1, 1);
      final rotatedMetrics = VisualInspectionService.inspect(
        VisualInspectionRequest(
          bytes,
          FishPart.gills,
          region: bottom,
          quarterTurns: 1,
        ),
      );
      expect(rotatedMetrics.hue, anyOf(lessThan(2), greaterThan(358)));
      expect(rotatedMetrics.value, closeTo(measured.value!, .01));
    },
  );

  test(
    'no exact export has an accepted class map; score rank cannot add names',
    () {
      for (final model in ExperimentalFishModel.values) {
        for (var index = 0; index < 3; index++) {
          expect(model.classNameForOutput(index), isNull);
        }
        final ai = ExperimentalAiResult(
          model: model,
          status: ExperimentalAiStatus.completed,
          message: 'Test scores only',
          scores: [.5, .5, 0],
        );
        expect(ai.leadingOutputIndices, [0, 1]);
        expect(
          ai.model.classNameForOutput(ai.leadingOutputIndices.first),
          isNull,
        );
        for (final scores in <List<double>>[
          [double.nan, 0, 1],
          [.4, .4, .4],
          [1, 0],
          [-.1, .1, 1],
        ]) {
          expect(
            ExperimentalAiResult(
              model: model,
              status: ExperimentalAiStatus.completed,
              message: 'Invalid test data',
              scores: scores,
            ).leadingOutputIndices,
            isEmpty,
          );
        }
      }
    },
  );
}
