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

/// Experimental heuristic, not a validated food safety model.
/// Hue is circular; saturation/value are normalized to [0,1].
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
      image.width < 200 ||
      image.height < 200 ||
      image.width * image.height > 16000000) {
    throw const FormatException(
      'Choose a valid image from 200 × 200 up to 16 megapixels.',
    );
  }
  return img.bakeOrientation(image);
}

GillAnalysis analyzeGills(Uint8List bytes) {
  final image = _decode(bytes);
  final x = (image.width - 200) ~/ 2, y = (image.height - 200) ~/ 2;
  var count = 0, reds = 0;
  var sine = 0.0, cosine = 0.0, saturation = 0.0, value = 0.0;
  for (var row = y; row < y + 200; row++) {
    for (var col = x; col < x + 200; col++) {
      final p = image.getPixel(col, row);
      final r = p.r / 255, g = p.g / 255, b = p.b / 255;
      final hi = math.max(r, math.max(g, b)), lo = math.min(r, math.min(g, b));
      final delta = hi - lo;
      final s = hi == 0 ? 0.0 : delta / hi;
      if (s < 0.2 || hi < 0.15 || hi > 0.98 && s < 0.35) continue;
      final hue =
          (hi == r
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
      if (hue <= 20 || hue >= 340) reds++;
    }
  }
  if (count < 8000 || math.sqrt(sine * sine + cosine * cosine) / count < 0.15) {
    throw const FormatException(
      'ROI has insufficient usable color or ambiguous hues. Center the gills and improve lighting.',
    );
  }
  final fraction = reds / count;
  return GillAnalysis(
    hue: (math.atan2(sine, cosine) * 180 / math.pi) % 360,
    saturation: saturation / count,
    value: value / count,
    redFraction: fraction,
    usableFraction: count / 40000,
    classification: fraction >= 0.6
        ? 'Fresh'
        : fraction >= 0.3
        ? 'Moderate'
        : 'Spoiled',
  );
}
