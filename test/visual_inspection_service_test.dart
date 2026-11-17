import 'dart:typed_data';

import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/services/visual_inspection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('corrupt images are inconclusive rather than classified', () {
    final result = VisualInspectionService.inspect(
      VisualInspectionRequest(Uint8List.fromList([1, 2, 3]), FishPart.gills),
    );
    expect(result.classification, 'Inconclusive');
    expect(result.isImageUsable, isFalse);
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
