import 'package:image/image.dart' as img;

/// Deliberately synthetic pixel fixture, not a fish or validation reference.
/// Only the central 128 x 128 is colored; the background must stay excluded.
img.Image regionFixture() {
  final image = img.Image(width: 256, height: 256);
  img.fill(image, color: img.ColorRgb8(100, 100, 100));
  for (var y = 64; y < 192; y++) {
    for (var x = 64; x < 192; x++) {
      final red = ((x ~/ 4) + (y ~/ 4)).isEven;
      image.setPixelRgb(x, y, red ? 200 : 20, red ? 20 : 120, 20);
    }
  }
  return image;
}
