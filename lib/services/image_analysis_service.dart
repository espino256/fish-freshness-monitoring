import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/classification.dart';

class ImageAnalysisService {
  const ImageAnalysisService();

  static const roiSize = 200;

  HueAnalysis analyze(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object catch (error) {
      throw FormatException('This image could not be decoded: $error');
    }
    if (decoded == null) {
      throw const FormatException('This image could not be decoded.');
    }
    if (decoded.width < roiSize || decoded.height < roiSize) {
      throw const FormatException(
        'Image must be at least 200 × 200 pixels to analyze the ROI.',
      );
    }
    final x = (decoded.width - roiSize) ~/ 2;
    final y = (decoded.height - roiSize) ~/ 2;
    final pixels = <(int, int, int)>[];
    var chromaticPixelCount = 0;
    for (var row = y; row < y + roiSize; row++) {
      for (var column = x; column < x + roiSize; column++) {
        final pixel = decoded.getPixel(column, row);
        final red = pixel.r.toInt();
        final green = pixel.g.toInt();
        final blue = pixel.b.toInt();
        final maximum = red > green
            ? (red > blue ? red : blue)
            : (green > blue ? green : blue);
        final minimum = red < green
            ? (red < blue ? red : blue)
            : (green < blue ? green : blue);
        if (maximum - minimum >= 16) {
          chromaticPixelCount++;
        }
        pixels.add((red, green, blue));
      }
    }
    if (chromaticPixelCount < roiSize * roiSize * 0.2) {
      throw const FormatException(
        'The selected ROI is too dark or low in color contrast for a reliable '
        'hue measurement. Improve lighting and recapture the gill cover.',
      );
    }
    final meanHue = meanHueFromRgb(pixels);
    if (meanHue == null) {
      throw const FormatException('No valid pixels were available to analyze.');
    }
    return HueAnalysis(
      meanHue: meanHue,
      width: decoded.width,
      height: decoded.height,
      regionX: x,
      regionY: y,
    );
  }
}
