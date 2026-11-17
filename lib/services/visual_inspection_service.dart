import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/visual_inspection.dart';

/// Validates a user-selected fish region without claiming object detection.
///
/// The bundled model has no accompanying label map, metadata, or validation
/// evidence. Until those are supplied, this service deliberately returns an
/// inconclusive result rather than mapping pixels to freshness classes.
class VisualInspectionService {
  const VisualInspectionService();

  static VisualInspectionResult inspect(VisualInspectionRequest request) {
    img.Image? image;
    try {
      image = img.decodeImage(request.bytes);
    } on Object {
      image = null;
    }
    if (image == null) {
      return _inconclusive(request.part, 0, 0, 'The image cannot be decoded. Choose a valid JPEG or PNG.');
    }
    image = img.bakeOrientation(image);
    if (image.width < 100 || image.height < 100 || image.width * image.height > 16000000) {
      return _inconclusive(request.part, image.width, image.height, 'Use an image from 100 × 100 pixels up to 16 megapixels.');
    }

    var sum = 0.0;
    var squaredSum = 0.0;
    var count = 0;
    final step = image.width * image.height > 500000 ? 4 : 2;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        final luminance = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b) / 255;
        sum += luminance;
        squaredSum += luminance * luminance;
        count++;
      }
    }
    final mean = sum / count;
    final variance = squaredSum / count - mean * mean;
    if (mean < 0.08) {
      return _inconclusive(request.part, image.width, image.height, 'The image is too dark. Use even lighting and retake the selected fish part.');
    }
    if (mean > 0.96) {
      return _inconclusive(request.part, image.width, image.height, 'The image is overexposed. Reduce glare and retake the selected fish part.');
    }
    if (variance < 0.002) {
      return _inconclusive(request.part, image.width, image.height, 'The image has too little detail and may be blurred or unfocused. Retake it closer to the selected fish part.');
    }
    return _inconclusive(
      request.part,
      image.width,
      image.height,
      'Image quality passed basic checks, but no validated ${request.part.label.toLowerCase()} model is deployed. Freshness is inconclusive.',
      usable: true,
    );
  }

  static VisualInspectionResult _inconclusive(
    FishPart part,
    int width,
    int height,
    String reason, {
    bool usable = false,
  }) => VisualInspectionResult(
    part: part,
    width: width,
    height: height,
    isImageUsable: usable,
    reason: reason,
  );
}

class VisualInspectionRequest {
  const VisualInspectionRequest(this.bytes, this.part);
  final Uint8List bytes;
  final FishPart part;
}
