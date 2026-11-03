import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class GillAnalysis {
  const GillAnalysis({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.redFraction,
    required this.usableFraction,
    required this.classification,
  });
  final double hue, saturation, value, redFraction, usableFraction;
  final String classification;
}

/// Prepares snapshot JPEG with baked image orientation
Uint8List prepareGillSnapshot(Uint8List bytes) {
  final image = _decode(bytes);
  return img.encodeJpg(img.bakeOrientation(image), quality: 90);
}

img.Image _decode(Uint8List bytes) {
  if (bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Image exceeds 10 MiB.');
  }
  img.Image? image;
  try {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 16000000) {
      throw const FormatException('Invalid or oversized image.');
    }
    image = decoder!.decodeFrame(0);
  } catch (_) {
    throw const FormatException(
      'Image could not be decoded. Use a valid JPEG or PNG.',
    );
  }
  if (image == null ||
      image.width < 100 ||
      image.height < 100 ||
      image.width * image.height > 16000000) {
    throw const FormatException(
      'Choose a valid image from 100 × 100 up to 16 megapixels.',
    );
  }
  return img.bakeOrientation(image);
}

/// Adaptive HSV Gill & Freshness Image Analysis
GillAnalysis analyzeGills(Uint8List bytes) {
  final image = _decode(bytes);

  // Pass 1: Strict center 200x200 ROI
  final centerWidth = math.min(200, image.width);
  final centerHeight = math.min(200, image.height);
  final startX = (image.width - centerWidth) ~/ 2;
  final startY = (image.height - centerHeight) ~/ 2;

  var (count, reds, sine, cosine, saturation, value, totalPixels) =
      _scanRegion(image, startX, startY, centerWidth, centerHeight, strict: true);

  // Pass 2: If strict center ROI yielded too few pixels, use relaxed color threshold
  if (count < 500) {
    final relaxed = _scanRegion(
      image,
      startX,
      startY,
      centerWidth,
      centerHeight,
      strict: false,
    );
    count = relaxed.$1;
    reds = relaxed.$2;
    sine = relaxed.$3;
    cosine = relaxed.$4;
    saturation = relaxed.$5;
    value = relaxed.$6;
    totalPixels = relaxed.$7;
  }

  // Pass 3: If center ROI is mostly ice or empty background, perform adaptive full image scan
  if (count < 300) {
    final fullScan = _scanRegion(
      image,
      0,
      0,
      image.width,
      image.height,
      strict: false,
    );
    count = fullScan.$1;
    reds = fullScan.$2;
    sine = fullScan.$3;
    cosine = fullScan.$4;
    saturation = fullScan.$5;
    value = fullScan.$6;
    totalPixels = fullScan.$7;
  }

  // Throw exception if an image is completely pitch-black, dark, or neutral monochrome grey without colors
  if (count < 50 || (saturation / (count == 0 ? 1 : count)) < 0.02) {
    throw const FormatException(
      'ROI has insufficient usable color or ambiguous hues. Center the gills and improve lighting.',
    );
  }

  final fraction = reds / count;
  final avgHue = (math.atan2(sine, cosine) * 180 / math.pi) % 360;
  final avgSat = saturation / count;
  final avgVal = value / count;

  // Freshness classification based on red/pink hue fraction and HSV metrics
  final String classification;
  if (fraction >= 0.28 || ((avgHue <= 35 || avgHue >= 325) && avgSat >= 0.12)) {
    classification = 'Fresh';
  } else if (fraction >= 0.12 || (avgHue <= 60 || avgHue >= 300)) {
    classification = 'Moderate';
  } else {
    classification = 'Spoiled';
  }

  return GillAnalysis(
    hue: avgHue,
    saturation: avgSat,
    value: avgVal,
    redFraction: fraction,
    usableFraction: (count / totalPixels).clamp(0.0, 1.0),
    classification: classification,
  );
}

(int, int, double, double, double, double, int) _scanRegion(
  img.Image image,
  int startX,
  int startY,
  int width,
  int height, {
  required bool strict,
}) {
  final x0 = startX.clamp(0, image.width - 1);
  final y0 = startY.clamp(0, image.height - 1);
  final x1 = (startX + width).clamp(1, image.width);
  final y1 = (startY + height).clamp(1, image.height);

  var count = 0, reds = 0;
  var sine = 0.0, cosine = 0.0, saturation = 0.0, value = 0.0;
  final totalPixels = (x1 - x0) * (y1 - y0);

  // Subsample step for large full-image scans to maintain high performance
  final step = (totalPixels > 200000) ? 2 : 1;

  for (var row = y0; row < y1; row += step) {
    for (var col = x0; col < x1; col += step) {
      final p = image.getPixel(col, row);
      final r = p.r / 255, g = p.g / 255, b = p.b / 255;
      final hi = math.max(r, math.max(g, b)), lo = math.min(r, math.min(g, b));
      final delta = hi - lo;
      final s = hi == 0 ? 0.0 : delta / hi;

      if (strict) {
        if (s < 0.10 || hi < 0.08 || (hi > 0.98 && s < 0.20)) continue;
      } else {
        if (hi < 0.04 || (hi > 0.99 && s < 0.01)) continue;
      }

      final hue = delta == 0
          ? 0.0
          : (hi == r
                  ? 60 * (((g - b) / delta) % 6)
                  : hi == g
                      ? 60 * ((b - r) / delta + 2)
                      : 60 * ((r - g) / delta + 4)) %
              360;

      sine += math.sin(hue * math.pi / 180);
      cosine += math.cos(hue * math.pi / 180);
      saturation += s;
      value += hi;
      count++;

      // Red/Pink/Gill hue sector: [0°, 35°] ∪ [325°, 360°]
      if (hue <= 35 || hue >= 325) reds++;
    }
  }

  return (count, reds, sine, cosine, saturation, value, totalPixels);
}
