import 'package:aqua_sense/models/fish_sample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('device image upload records', () {
    test('parses the camera metadata and UTC timestamp', () {
      final upload = DeviceImageUpload.fromFirebase('upload-1', {
        'sampleId': 'FS-20261020-ABC',
        'storagePath': 'samples/FS-20261020-ABC/images/camera-123.jpg',
        'timestamp': 1792460000000,
        'deviceId': 'camera-uid',
      });

      expect(upload.id, 'upload-1');
      expect(upload.sampleId, 'FS-20261020-ABC');
      expect(
        upload.storagePath,
        'samples/FS-20261020-ABC/images/camera-123.jpg',
      );
      expect(
        upload.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1792460000000, isUtc: true),
      );
      expect(upload.deviceId, 'camera-uid');
    });

    test('rejects malformed metadata and paths for another sample', () {
      expect(
        () => DeviceImageUpload.fromFirebase('upload-1', {
          'sampleId': 'FS-1',
          'storagePath': 'samples/FS-2/images/camera.jpg',
          'timestamp': 1792460000000,
          'deviceId': 'camera-uid',
        }),
        throwsFormatException,
      );
      expect(
        () => DeviceImageUpload.fromFirebase('upload-2', const {}),
        throwsFormatException,
      );
      expect(
        () => DeviceImageUpload.fromFirebase('upload-3', {
          'sampleId': '../private',
          'storagePath': 'samples/../private/images/camera.jpg',
          'timestamp': 1792460000000,
          'deviceId': 'camera-uid',
        }),
        throwsFormatException,
      );
    });
  });
}
