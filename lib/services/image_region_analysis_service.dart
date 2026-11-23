import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/image_region.dart';

class HsvPixel {
  const HsvPixel(this.hue, this.saturation, this.value);
  final double? hue;
  final double saturation, value;
}

/// Describes a manually selected region; never classifies fish freshness.
class ImageRegionAnalysisService {
  // Acquisition/mask defaults, not independently validated freshness criteria.
  static const minimumSide = 16;
  static const minimumSamples = 50;
  static const minimumValue = 0.08;
  static const minimumHueSaturation = 0.10;
  static const glareValue = 0.98;
  static const glareSaturation = 0.20;
  static const minimumFocusVariance = 0.0001;

  static HsvPixel rgbToHsv(double r, double g, double b) {
    if (![r, g, b].every((c) => c.isFinite && c >= 0 && c <= 1)) {
      throw ArgumentError(
        'RGB channels must be finite normalized values in 0..1.',
      );
    }
    final hi = math.max(r, math.max(g, b));
    final lo = math.min(r, math.min(g, b));
    final delta = hi - lo;
    if (delta == 0) return HsvPixel(null, 0, hi);
    final hue = hi == r
        ? 60 * (((g - b) / delta) % 6)
        : hi == g
        ? 60 * ((b - r) / delta + 2)
        : 60 * ((r - g) / delta + 4);
    return HsvPixel(hue % 360, hi == 0 ? 0 : delta / hi, hi);
  }

  static bool isRedHue(double hue) =>
      hue.isFinite && (hue % 360 <= 35 || hue % 360 >= 325);

  static double? circularHueMean(Iterable<double> hues) {
    var sine = 0.0, cosine = 0.0;
    var count = 0;
    for (final hue in hues) {
      if (!hue.isFinite) continue;
      sine += math.sin(hue * math.pi / 180);
      cosine += math.cos(hue * math.pi / 180);
      count++;
    }
    return _hueMean(sine, cosine, count);
  }

  static double? _hueMean(double sine, double cosine, int count) {
    // Cancellation tolerance is numerical, not a freshness acceptance cutoff.
    if (count == 0 || math.sqrt(sine * sine + cosine * cosine) / count < 1e-6) {
      return null;
    }
    final hue = math.atan2(sine, cosine) * 180 / math.pi % 360;
    return (360 - hue).abs() < 1e-9 ? 0 : hue;
  }

  static bool _quality(img.Pixel pixel, HsvPixel hsv) =>
      pixel.aNormalized == 1 &&
      hsv.value >= minimumValue &&
      !(hsv.value > glareValue && hsv.saturation < glareSaturation);

  static ImageRegionMeasurements analyze(
    img.Image image,
    ImageRegion region, {
    Uint8List? selectionMask,
  }) {
    final bounds = region.pixels(image.width, image.height);
    if (bounds == null) {
      return const ImageRegionMeasurements(
        reason: 'Select a non-empty region inside the image.',
      );
    }
    if (bounds.width < minimumSide || bounds.height < minimumSide) {
      return ImageRegionMeasurements(
        bounds: bounds,
        reason:
            'The selected region is too small. Select at least 16 × 16 image pixels.',
      );
    }
    if (selectionMask != null &&
        selectionMask.length != image.width * image.height) {
      return ImageRegionMeasurements(
        bounds: bounds,
        reason:
            'The selection mask does not match the oriented image dimensions.',
      );
    }
    var eligible = 0, usable = 0, hues = 0, reds = 0;
    var sumS = 0.0, sumV = 0.0, sine = 0.0, cosine = 0.0;
    bool selected(int x, int y) =>
        selectionMask == null || selectionMask[y * image.width + x] != 0;
    for (var y = bounds.top; y < bounds.bottom; y++) {
      for (var x = bounds.left; x < bounds.right; x++) {
        if (!selected(x, y)) continue;
        eligible++;
        final p = image.getPixel(x, y);
        final hsv = rgbToHsv(
          p.rNormalized.toDouble(),
          p.gNormalized.toDouble(),
          p.bNormalized.toDouble(),
        );
        if (!_quality(p, hsv)) continue;
        usable++;
        sumS += hsv.saturation;
        sumV += hsv.value;
        if (hsv.hue == null || hsv.saturation < minimumHueSaturation) continue;
        final h = hsv.hue!;
        sine += math.sin(h * math.pi / 180);
        cosine += math.cos(h * math.pi / 180);
        hues++;
        if (isRedHue(h)) reds++;
      }
    }
    if (eligible == 0) {
      return ImageRegionMeasurements(
        bounds: bounds,
        reason:
            'No eligible pixels remain in the manually selected region/mask.',
      );
    }
    final fraction = usable / eligible;
    if (usable < minimumSamples) {
      return ImageRegionMeasurements(
        bounds: bounds,
        eligiblePixels: eligible,
        usablePixels: usable,
        huePixels: hues,
        usableFraction: fraction,
        reason:
            'Only $usable eligible pixels pass exposure/opacity checks. At least 50 are needed; improve lighting or change the region.',
      );
    }

    // Real variance-of-Laplacian focus proxy, sampled on a documented grid.
    // Neighbours must also be eligible/opaque/exposed to avoid mask-edge bias.
    var focusN = 0;
    var lapSum = 0.0, lapSquared = 0.0;
    final step = bounds.count > 500000 ? 4 : 2;
    double? luminance(int x, int y) {
      if (!selected(x, y)) return null;
      final p = image.getPixel(x, y);
      final hsv = rgbToHsv(
        p.rNormalized.toDouble(),
        p.gNormalized.toDouble(),
        p.bNormalized.toDouble(),
      );
      if (!_quality(p, hsv)) return null;
      return 0.2126 * p.rNormalized +
          0.7152 * p.gNormalized +
          0.0722 * p.bNormalized;
    }

    for (var y = bounds.top + 1; y < bounds.bottom - 1; y += step) {
      for (var x = bounds.left + 1; x < bounds.right - 1; x += step) {
        final values = [
          luminance(x, y),
          luminance(x - 1, y),
          luminance(x + 1, y),
          luminance(x, y - 1),
          luminance(x, y + 1),
        ];
        if (values.any((v) => v == null)) continue;
        final lap =
            values[1]! + values[2]! + values[3]! + values[4]! - 4 * values[0]!;
        lapSum += lap;
        lapSquared += lap * lap;
        focusN++;
      }
    }
    final focus = focusN < minimumSamples
        ? null
        : math
              .max(0.0, lapSquared / focusN - math.pow(lapSum / focusN, 2))
              .toDouble();
    if (focus == null || focus < minimumFocusVariance) {
      return ImageRegionMeasurements(
        bounds: bounds,
        eligiblePixels: eligible,
        usablePixels: usable,
        huePixels: hues,
        focusVariance: focus,
        reason:
            'The region has too little spatial detail for reporting these descriptors. Blur or a flat surface may be responsible; retake or choose a sharper region.',
      );
    }
    final hue = hues >= minimumSamples ? _hueMean(sine, cosine, hues) : null;
    return ImageRegionMeasurements(
      bounds: bounds,
      meanHue: hue,
      meanSaturation: sumS / usable,
      meanValue: sumV / usable,
      redFraction: hues >= minimumSamples ? reds / hues : null,
      usableFraction: fraction,
      eligiblePixels: eligible,
      usablePixels: usable,
      huePixels: hues,
      focusVariance: focus,
      reason: hue == null
          ? 'ROI descriptors calculated. Hue is unavailable: insufficient saturated pixels or an ambiguous circular mean.'
          : 'Descriptors calculated from the manually selected ROI. Anatomy is not automatically verified.',
    );
  }
}
