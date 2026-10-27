import 'dart:typed_data';

import 'package:aqua_sense/services/image_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const service = ImageAnalysisService();

  test('rejects corrupt image bytes with a useful validation error', () {
    expect(
      () => service.analyze(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('rejects an image smaller than the documented ROI', () {
    final small = img.Image(width: 199, height: 200);
    final bytes = img.encodePng(small);
    expect(() => service.analyze(bytes), throwsFormatException);
  });

  test('analyzes a centered 200 by 200 region deterministically', () {
    final source = img.Image(width: 240, height: 220);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    final result = service.analyze(img.encodePng(source));
    expect(result.width, 240);
    expect(result.height, 220);
    expect(result.regionX, 20);
    expect(result.regionY, 10);
    expect(result.meanHue, 0);
  });
}
