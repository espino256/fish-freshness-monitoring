import 'dart:math' as math;

enum FreshnessClass { fresh, moderate, spoiled, review }

extension FreshnessClassLabel on FreshnessClass {
  String get label => switch (this) {
    FreshnessClass.fresh => 'Fresh',
    FreshnessClass.moderate => 'Moderate',
    FreshnessClass.spoiled => 'Spoiled',
    FreshnessClass.review => 'Review required',
  };
}

class FreshnessThresholds {
  const FreshnessThresholds({
    this.phFreshMin = 6.2,
    this.phFreshMaxExclusive = 6.5,
    this.phModerateMaxInclusive = 7.0,
    this.hueSpoiledMinExclusive = 5,
    this.hueFreshMinInclusive = 5,
    this.hueFreshMaxExclusive = 25,
    this.hueModerateMaxInclusive = 45,
  });

  final double phFreshMin;
  final double phFreshMaxExclusive;
  final double phModerateMaxInclusive;
  final double hueSpoiledMinExclusive;
  final double hueFreshMinInclusive;
  final double hueFreshMaxExclusive;
  final double hueModerateMaxInclusive;

  bool get isValid =>
      phFreshMin >= 0 &&
      phModerateMaxInclusive <= 14 &&
      phFreshMin < phFreshMaxExclusive &&
      phFreshMaxExclusive <= phModerateMaxInclusive &&
      hueSpoiledMinExclusive >= 0 &&
      hueModerateMaxInclusive <= 360 &&
      hueSpoiledMinExclusive <= hueFreshMinInclusive &&
      hueFreshMinInclusive < hueFreshMaxExclusive &&
      hueFreshMaxExclusive <= hueModerateMaxInclusive;

  FreshnessClass? classifyPh(double? value) {
    if (value == null || !value.isFinite || value < 0 || value > 14) {
      return null;
    }
    if (value < phFreshMin) return FreshnessClass.review;
    if (value < phFreshMaxExclusive) return FreshnessClass.fresh;
    if (value <= phModerateMaxInclusive) return FreshnessClass.moderate;
    return FreshnessClass.spoiled;
  }

  FreshnessClass? classifyHue(double? value) {
    if (value == null || !value.isFinite || value < 0 || value > 360) {
      return null;
    }
    if (value < hueSpoiledMinExclusive) return FreshnessClass.spoiled;
    if (value < hueFreshMinInclusive) return FreshnessClass.review;
    if (value < hueFreshMaxExclusive) return FreshnessClass.fresh;
    if (value <= hueModerateMaxInclusive) return FreshnessClass.moderate;
    return FreshnessClass.spoiled;
  }

  Map<String, double> toJson() => {
    'phFreshMin': phFreshMin,
    'phFreshMaxExclusive': phFreshMaxExclusive,
    'phModerateMaxInclusive': phModerateMaxInclusive,
    'hueSpoiledMinExclusive': hueSpoiledMinExclusive,
    'hueFreshMinInclusive': hueFreshMinInclusive,
    'hueFreshMaxExclusive': hueFreshMaxExclusive,
    'hueModerateMaxInclusive': hueModerateMaxInclusive,
  };

  factory FreshnessThresholds.fromJson(Map<String, dynamic> json) {
    final thresholds = FreshnessThresholds(
      phFreshMin: (json['phFreshMin'] as num?)?.toDouble() ?? 6.2,
      phFreshMaxExclusive:
          (json['phFreshMaxExclusive'] as num?)?.toDouble() ?? 6.5,
      phModerateMaxInclusive:
          (json['phModerateMaxInclusive'] as num?)?.toDouble() ?? 7.0,
      hueSpoiledMinExclusive:
          (json['hueSpoiledMinExclusive'] as num?)?.toDouble() ?? 5,
      hueFreshMinInclusive:
          (json['hueFreshMinInclusive'] as num?)?.toDouble() ?? 5,
      hueFreshMaxExclusive:
          (json['hueFreshMaxExclusive'] as num?)?.toDouble() ?? 25,
      hueModerateMaxInclusive:
          (json['hueModerateMaxInclusive'] as num?)?.toDouble() ?? 45,
    );
    if (!thresholds.isValid) {
      throw const FormatException(
        'Saved classification thresholds are invalid.',
      );
    }
    return thresholds;
  }
}

class HueAnalysis {
  const HueAnalysis({
    required this.meanHue,
    required this.width,
    required this.height,
    required this.regionX,
    required this.regionY,
  });

  final double meanHue;
  final int width;
  final int height;
  final int regionX;
  final int regionY;
}

double? meanHueFromRgb(Iterable<(int, int, int)> pixels) {
  var sineTotal = 0.0;
  var cosineTotal = 0.0;
  var count = 0;
  for (final (red, green, blue) in pixels) {
    if (red < 0 ||
        red > 255 ||
        green < 0 ||
        green > 255 ||
        blue < 0 ||
        blue > 255) {
      return null;
    }
    final r = red / 255;
    final g = green / 255;
    final b = blue / 255;
    final maximum = math.max(r, math.max(g, b));
    final minimum = math.min(r, math.min(g, b));
    final delta = maximum - minimum;
    var hue = 0.0;
    if (delta != 0) {
      if (maximum == r) {
        hue = 60 * (((g - b) / delta) % 6);
      } else if (maximum == g) {
        hue = 60 * ((b - r) / delta + 2);
      } else {
        hue = 60 * ((r - g) / delta + 4);
      }
    }
    final radians = (hue < 0 ? hue + 360 : hue) * math.pi / 180;
    sineTotal += math.sin(radians);
    cosineTotal += math.cos(radians);
    count++;
  }
  if (count == 0) return null;
  final meanRadians = math.atan2(sineTotal / count, cosineTotal / count);
  final meanDegrees = meanRadians * 180 / math.pi;
  return meanDegrees < 0 ? meanDegrees + 360 : meanDegrees;
}
