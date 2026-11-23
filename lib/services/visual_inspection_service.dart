import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/visual_inspection.dart';
import '../models/image_region.dart';
import 'image_region_analysis_service.dart';

/// Validates a user-selected fish region without claiming object detection.
///
/// The bundled model has conversion metadata, but no label map, fish-part
/// coverage, or validation evidence. See docs/AI_MODEL_REQUIREMENTS.md.
/// This synchronous service only prepares images. Experimental inference lives
/// in AiInferenceService. These checks are not freshness or part detection.
class VisualInspectionService {
  const VisualInspectionService();

  /// Bakes EXIF/user rotation for the preview; no model or HSV work here.
  static InspectionImagePreview preview(VisualInspectionRequest request) {
    final decoded = _decode(request);
    final image = decoded.image;
    return InspectionImagePreview(
      image == null ? null : img.encodePng(image),
      decoded.width,
      decoded.height,
      decoded.reason,
    );
  }

  static VisualInspectionResult inspect(VisualInspectionRequest request) =>
      _inspect(request);

  /// Pure Dart work only: safe to call via compute on native platforms.
  static PreparedVisualInspection prepare(VisualInspectionRequest request) {
    Float32List? input;
    final inspection = _inspect(
      request,
      onUsableImage: (image) {
        input = prepareRgbInput(image);
      },
    );
    return PreparedVisualInspection(inspection, input);
  }

  /// TensorFlow's default half-pixel bilinear resize, retaining float pixels.
  /// Notebook loaders use RGB, tf.image.resize and float32, with no division.
  /// The graph already rescales; supply RGB float32 in the 0–255 range.
  static Float32List prepareRgbInput(img.Image image) {
    final input = Float32List(224 * 224 * 3);
    var index = 0;
    for (var y = 0; y < 224; y++) {
      final sourceY = math.max(0.0, (y + 0.5) * image.height / 224 - 0.5);
      final y0 = sourceY.floor();
      final y1 = math.min(y0 + 1, image.height - 1);
      final dy = sourceY - y0;
      for (var x = 0; x < 224; x++) {
        final sourceX = math.max(0.0, (x + 0.5) * image.width / 224 - 0.5);
        final x0 = sourceX.floor();
        final x1 = math.min(x0 + 1, image.width - 1);
        final dx = sourceX - x0;
        final a = image.getPixel(x0, y0);
        final b = image.getPixel(x1, y0);
        final c = image.getPixel(x0, y1);
        final d = image.getPixel(x1, y1);
        double interpolate(num aa, num bb, num cc, num dd) {
          final top = aa + (bb - aa) * dx;
          final bottom = cc + (dd - cc) * dx;
          return (top + (bottom - top) * dy) * 255;
        }

        input[index++] = interpolate(
          a.rNormalized,
          b.rNormalized,
          c.rNormalized,
          d.rNormalized,
        );
        input[index++] = interpolate(
          a.gNormalized,
          b.gNormalized,
          c.gNormalized,
          d.gNormalized,
        );
        input[index++] = interpolate(
          a.bNormalized,
          b.bNormalized,
          c.bNormalized,
          d.bNormalized,
        );
      }
    }
    return input;
  }

  static VisualInspectionResult _inspect(
    VisualInspectionRequest request, {
    void Function(img.Image)? onUsableImage,
  }) {
    final decoded = _decode(request);
    final image = decoded.image;
    if (image == null) {
      return _inconclusive(
        request.part,
        decoded.width,
        decoded.height,
        decoded.reason!,
      );
    }

    var sum = 0.0;
    var squaredSum = 0.0;
    var count = 0;
    final step = image.width * image.height > 500000 ? 4 : 2;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        final luminance =
            0.2126 * p.rNormalized +
            0.7152 * p.gNormalized +
            0.0722 * p.bNormalized;
        sum += luminance;
        squaredSum += luminance * luminance;
        count++;
      }
    }
    final mean = sum / count;
    final variance = squaredSum / count - mean * mean;
    if (mean < 0.08) {
      return _inconclusive(
        request.part,
        image.width,
        image.height,
        'The image is too dark. Use even lighting and retake the selected fish part.',
      );
    }
    if (mean > 0.96) {
      return _inconclusive(
        request.part,
        image.width,
        image.height,
        'The image is overexposed. Reduce glare and retake the selected fish part.',
      );
    }
    if (variance < 0.002) {
      return _inconclusive(
        request.part,
        image.width,
        image.height,
        'The image has too little detail and may be blurred or unfocused. Retake it closer to the selected fish part.',
      );
    }
    onUsableImage?.call(image);
    final measurements = request.region == null
        ? const ImageRegionMeasurements(
            reason:
                'Select and apply a fish-part ROI to calculate image descriptors.',
          )
        : ImageRegionAnalysisService.analyze(
            image,
            request.region!,
            selectionMask: request.selectionMask,
          );
    return VisualInspectionResult(
      part: request.part,
      width: image.width,
      height: image.height,
      isImageUsable: true,
      measurements: measurements,
      reason:
          'Basic image checks passed. No validated model is available for ${request.part.label}. '
          'The selected fish part has not been verified. Freshness is inconclusive.',
    );
  }

  static _DecodedImage _decode(VisualInspectionRequest request) {
    if (request.bytes.length > 10 * 1024 * 1024) {
      return const _DecodedImage(
        null,
        0,
        0,
        'Image exceeds 10 MiB. Choose a smaller JPEG or PNG.',
      );
    }
    img.Image? image;
    try {
      final decoder = img.findDecoderForData(request.bytes);
      if (decoder is! img.JpegDecoder && decoder is! img.PngDecoder) {
        return const _DecodedImage(
          null,
          0,
          0,
          'Choose a valid JPEG or PNG image.',
        );
      }
      final info = decoder!.startDecode(request.bytes);
      if (info != null) {
        // Inspect dimensions before allocating the decoded pixel buffer.
        if (info.width < 100 ||
            info.height < 100 ||
            info.width * info.height > 16000000) {
          return _DecodedImage(
            null,
            info.width,
            info.height,
            'Use an image from 100 × 100 pixels up to 16 megapixels.',
          );
        }
        if (info.numFrames > 1) {
          return _DecodedImage(
            null,
            info.width,
            info.height,
            'Choose a single still JPEG or PNG image.',
          );
        }
        image = decoder.decodeFrame(0);
      }
      if (image != null) image = img.bakeOrientation(image);
      if (image != null && request.quarterTurns % 4 != 0) {
        image = img.copyRotate(image, angle: (request.quarterTurns % 4) * 90);
      }
    } on Object {
      image = null;
    }
    if (image == null) {
      return const _DecodedImage(
        null,
        0,
        0,
        'The image cannot be decoded. Choose a valid JPEG or PNG.',
      );
    }
    return _DecodedImage(image, image.width, image.height, null);
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
  const VisualInspectionRequest(
    this.bytes,
    this.part, {
    this.region,
    this.quarterTurns = 0,
    this.selectionMask,
  });
  final Uint8List bytes;
  final FishPart part;
  final ImageRegion? region;
  final int quarterTurns;
  final Uint8List? selectionMask;
}

class InspectionImagePreview {
  const InspectionImagePreview(
    this.bytes,
    this.width,
    this.height,
    this.reason,
  );
  final Uint8List? bytes;
  final int width, height;
  final String? reason;
}

class _DecodedImage {
  const _DecodedImage(this.image, this.width, this.height, this.reason);
  final img.Image? image;
  final int width, height;
  final String? reason;
}

class PreparedVisualInspection {
  const PreparedVisualInspection(this.inspection, this.input);
  final VisualInspectionResult inspection;
  final Float32List? input;
}
