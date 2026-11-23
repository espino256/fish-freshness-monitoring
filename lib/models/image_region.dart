/// A user-selected rectangle in the displayed, oriented image (0..1).
/// Selection is manual; it is never evidence of verified fish anatomy.
class ImageRegion {
  const ImageRegion(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;

  bool get isValid =>
      [left, top, right, bottom].every((v) => v.isFinite && v >= 0 && v <= 1) &&
      right > left &&
      bottom > top;

  RegionPixels? pixels(int width, int height) {
    if (!isValid || width <= 0 || height <= 0) return null;
    return RegionPixels(
      (left * width).floor(),
      (top * height).floor(),
      (right * width).ceil().clamp(0, width),
      (bottom * height).ceil().clamp(0, height),
    );
  }
}

class RegionPixels {
  const RegionPixels(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;
  int get count => width * height;
}

/// Pixel descriptors only: no freshness, confidence or pH fields.
class ImageRegionMeasurements {
  const ImageRegionMeasurements({
    required this.reason,
    this.bounds,
    this.meanHue,
    this.meanSaturation,
    this.meanValue,
    this.redFraction,
    this.usableFraction,
    this.eligiblePixels = 0,
    this.usablePixels = 0,
    this.huePixels = 0,
    this.focusVariance,
  });

  final String reason;
  final RegionPixels? bounds;
  final double? meanHue, meanSaturation, meanValue, redFraction, usableFraction;
  final int eligiblePixels, usablePixels, huePixels;
  final double? focusVariance;
}
